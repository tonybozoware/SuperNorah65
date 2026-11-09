// DexedSynth implementation. Written for Biryani64; the FM engine (msfa/) is
// Dexed's, Apache License 2.0.

#include "dexed_synth.h"

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

#include "msfa/env.h"
#include "msfa/exp2.h"
#include "msfa/freqlut.h"
#include "msfa/pitchenv.h"
#include "msfa/porta.h"
#include "msfa/sin.h"
#include "msfa/tuning.h"

using namespace godot;

namespace {

// Unpacked (VCED) layout: 6 operators of 21 bytes, OP6 first, then globals.
const char *OP_NAMES[21] = {
    "rate1", "rate2", "rate3", "rate4", "level1", "level2", "level3", "level4",
    "break_point", "left_depth", "right_depth", "left_curve", "right_curve",
    "rate_scaling", "amp_mod_sens", "velocity_sens", "output_level", "mode",
    "coarse", "fine", "detune",
};
const int OP_MAX[21] = { 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 3, 3, 7, 3, 7, 99, 1, 31, 99, 14 };

struct GlobalParam { const char *name; int index; int max; };
const GlobalParam GLOBALS[] = {
    { "pitch_rate1", 126, 99 }, { "pitch_rate2", 127, 99 }, { "pitch_rate3", 128, 99 }, { "pitch_rate4", 129, 99 },
    { "pitch_level1", 130, 99 }, { "pitch_level2", 131, 99 }, { "pitch_level3", 132, 99 }, { "pitch_level4", 133, 99 },
    { "algorithm", 134, 31 }, { "feedback", 135, 7 }, { "osc_sync", 136, 1 },
    { "lfo_speed", 137, 99 }, { "lfo_delay", 138, 99 }, { "lfo_pitch_depth", 139, 99 },
    { "lfo_amp_depth", 140, 99 }, { "lfo_sync", 141, 1 }, { "lfo_wave", 142, 5 },
    { "lfo_pitch_sens", 143, 7 }, { "transpose", 144, 48 },
};

bool tables_ready = false;
double tables_rate = 0.0;

void init_tables(double rate) {
    if (tables_ready && tables_rate == rate) {
        return;
    }
    Exp2::init();
    Tanh::init();
    Sin::init();
    Freqlut::init(rate);
    Lfo::init(rate);
    PitchEnv::init(rate);
    Env::init_sr(rate);
    Porta::init_sr(rate);
    tables_ready = true;
    tables_rate = rate;
}

} // namespace

DexedSynth::DexedSynth() {
    init_voice(voice_);
    cartridge_.assign(voice_, voice_ + VOICE_SIZE);
    names_.push_back("INIT VOICE");
    std::memset(block_, 0, sizeof(block_));
    std::memset(block_out_, 0, sizeof(block_out_));
}

DexedSynth::~DexedSynth() {}

void DexedSynth::ensure_engine() {
    if (engine_ready_) {
        return;
    }
    rate_ = AudioServer::get_singleton() ? AudioServer::get_singleton()->get_mix_rate() : 44100.0;
    init_tables(rate_);
    tuning_ = createStandardTuning();

    controllers_.pitch_cc = 0x2000;
    controllers_.pitch_range_up = 2;
    controllers_.pitch_range_dn = 2;
    controllers_.pitch_step = 0;
    controllers_.masterTune = 0;
    controllers_.modwheel_cc = 0;
    controllers_.breath_cc = 0;
    controllers_.foot_cc = 0;
    controllers_.aftertouch_cc = 0;
    controllers_.portamento_enable_cc = false;
    controllers_.portamento_cc = 0;
    controllers_.portamento_gliss_cc = false;
    controllers_.mpeEnabled = false;
    controllers_.wheel.range = 100;
    controllers_.wheel.pitch = true;
    controllers_.core = &core_;
    controllers_.refresh();

    voices_.clear();
    voices_.resize(MAX_POLYPHONY);
    for (Voice &v : voices_) {
        v.note = std::make_unique<Dx7Note>(tuning_, &mts_);
    }
    lfo_.reset(voice_ + 137);
    engine_ready_ = true;
}

// ------------------------------------------------------------------ notes
void DexedSynth::note_on(int note, int velocity) {
    std::lock_guard<std::mutex> lock(mutex_);
    ensure_engine();
    note = std::clamp(note, 0, 127);
    velocity = std::clamp(velocity, 1, 127);
    // Free voice first, then the oldest released one, then the oldest overall.
    int pick = -1;
    uint64_t oldest = UINT64_MAX;
    for (int i = 0; i < polyphony_; i++) {
        Voice &v = voices_[i];
        if (!v.keydown && !v.note->isPlaying()) {
            pick = i;
            break;
        }
    }
    if (pick < 0) {
        for (int i = 0; i < polyphony_; i++) {
            if (!voices_[i].keydown && voices_[i].started < oldest) {
                oldest = voices_[i].started;
                pick = i;
            }
        }
    }
    if (pick < 0) {
        for (int i = 0; i < polyphony_; i++) {
            if (voices_[i].started < oldest) {
                oldest = voices_[i].started;
                pick = i;
            }
        }
    }
    Voice &v = voices_[pick];
    v.note->init(voice_, note, velocity, 1, &controllers_);
    v.midinote = note;
    v.velocity = velocity;
    v.keydown = true;
    v.started = ++note_counter_;
    lfo_.keydown();
}

void DexedSynth::note_off(int note) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!engine_ready_) {
        return;
    }
    for (Voice &v : voices_) {
        if (v.keydown && v.midinote == note) {
            v.note->keyup();
            v.keydown = false;
        }
    }
}

void DexedSynth::all_notes_off() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!engine_ready_) {
        return;
    }
    for (Voice &v : voices_) {
        if (v.keydown) {
            v.note->keyup();
            v.keydown = false;
        }
    }
}

// ------------------------------------------------------------------ render
void DexedSynth::render(float *out, int frames) {
    std::lock_guard<std::mutex> lock(mutex_);
    ensure_engine();
    const float scale = volume_ / float(1 << 28);
    for (int f = 0; f < frames; f++) {
        if (block_pos_ >= N) {
            int32_t lfo_val = lfo_.getsample();
            int32_t lfo_delay = lfo_.getdelay();
            for (int j = 0; j < N; j++) {
                block_out_[j] = 0.0f;
            }
            for (Voice &v : voices_) {
                if (!v.keydown && !v.note->isPlaying()) {
                    continue;
                }
                for (int j = 0; j < N; j++) {
                    block_[j] = 0;
                }
                v.note->compute(block_, lfo_val, lfo_delay, &controllers_);
                for (int j = 0; j < N; j++) {
                    block_out_[j] += float(block_[j]) * scale;
                }
            }
            block_pos_ = 0;
        }
        float s = block_out_[block_pos_++];
        // Gentle limit so many loud voices can't clip harshly.
        out[f] = std::tanh(s);
    }
}

// ------------------------------------------------------------------ voices
void DexedSynth::init_voice(uint8_t *v) {
    std::memset(v, 0, VOICE_SIZE);
    for (int op = 0; op < 6; op++) {
        uint8_t *o = v + op * 21;
        o[0] = o[1] = o[2] = o[3] = 99;          // rates
        o[4] = o[5] = o[6] = 99;                  // levels
        o[7] = 0;
        o[8] = 39;                                // break point (C3)
        o[16] = (op == 5) ? 99 : 0;               // only OP1 sounds
        o[18] = 1;                                // coarse ratio 1
        o[20] = 7;                                // detune centre
    }
    for (int i = 0; i < 4; i++) {
        v[126 + i] = 99;
        v[130 + i] = 50;
    }
    v[134] = 0;     // algorithm 1
    v[136] = 1;     // osc key sync
    v[137] = 35;    // lfo speed
    v[141] = 1;     // lfo key sync
    v[143] = 3;     // pitch mod sensitivity
    v[144] = 24;    // transpose: C3 = middle
    const char *name = "INIT VOICE";
    for (int i = 0; i < 10; i++) {
        v[145 + i] = name[i];
    }
    v[155] = 0x3F;  // all six operators on
}

// DX7 32-voice bulk format (128 bytes per voice) -> 156-byte unpacked voice.
void DexedSynth::unpack_voice(const uint8_t *p, uint8_t *v) {
    for (int op = 0; op < 6; op++) {
        const uint8_t *s = p + op * 17;
        uint8_t *d = v + op * 21;
        for (int i = 0; i < 11; i++) {
            d[i] = s[i] & 0x7F;                   // rates, levels, BP, LD, RD
        }
        d[11] = s[11] & 0x03;                     // left curve
        d[12] = (s[11] >> 2) & 0x03;              // right curve
        d[13] = s[12] & 0x07;                     // rate scaling
        d[20] = (s[12] >> 3) & 0x0F;              // detune
        d[14] = s[13] & 0x03;                     // amp mod sensitivity
        d[15] = (s[13] >> 2) & 0x07;              // key velocity sensitivity
        d[16] = s[14] & 0x7F;                     // output level
        d[17] = s[15] & 0x01;                     // osc mode
        d[18] = (s[15] >> 1) & 0x1F;              // freq coarse
        d[19] = s[16] & 0x7F;                     // freq fine
    }
    for (int i = 0; i < 8; i++) {
        v[126 + i] = p[102 + i] & 0x7F;           // pitch EG rates, levels
    }
    v[134] = p[110] & 0x1F;                       // algorithm
    v[135] = p[111] & 0x07;                       // feedback
    v[136] = (p[111] >> 3) & 0x01;                // osc key sync
    v[137] = p[112] & 0x7F;                       // lfo speed
    v[138] = p[113] & 0x7F;                       // lfo delay
    v[139] = p[114] & 0x7F;                       // lfo pitch mod depth
    v[140] = p[115] & 0x7F;                       // lfo amp mod depth
    v[141] = p[116] & 0x01;                       // lfo key sync
    v[142] = (p[116] >> 1) & 0x07;                // lfo wave
    v[143] = (p[116] >> 4) & 0x07;                // pitch mod sensitivity
    v[144] = p[117] & 0x7F;                       // transpose
    for (int i = 0; i < 10; i++) {
        v[145 + i] = p[118 + i] & 0x7F;           // name
    }
    v[155] = 0x3F;
    for (int i = 0; i < VOICE_SIZE; i++) {
        v[i] = std::min<int>(v[i], param_max(i));
    }
}

int DexedSynth::param_max(int index) {
    if (index < 126) {
        return OP_MAX[index % 21];
    }
    for (const GlobalParam &g : GLOBALS) {
        if (g.index == index) {
            return g.max;
        }
    }
    if (index >= 145 && index <= 154) {
        return 127;
    }
    if (index == 155) {
        return 63;
    }
    return 127;
}

static String voice_name_of(const uint8_t *v) {
    char buf[11];
    for (int i = 0; i < 10; i++) {
        char c = char(v[145 + i]);
        buf[i] = (c >= 32 && c < 127) ? c : ' ';
    }
    buf[10] = 0;
    return String(buf).strip_edges();
}

int DexedSynth::load_cartridge(const String &path) {
    Ref<FileAccess> f = FileAccess::open(path, FileAccess::READ);
    if (f.is_null()) {
        UtilityFunctions::push_error("DexedSynth: can't open ", path);
        return 0;
    }
    PackedByteArray data = f->get_buffer(f->get_length());
    int n = load_cartridge_data(data);
    if (n > 0) {
        cartridge_path_ = path;
    }
    return n;
}

int DexedSynth::load_cartridge_data(const PackedByteArray &data) {
    const uint8_t *d = data.ptr();
    int64_t size = data.size();
    std::vector<uint8_t> cart;
    std::vector<String> names;
    if (size >= 4104 && d[0] == 0xF0 && d[1] == 0x43 && d[3] == 0x09) {
        d += 6;     // 32-voice bulk dump with sysex header
        size = 4096;
    } else if (size >= 163 && d[0] == 0xF0 && d[1] == 0x43 && d[3] == 0x00) {
        // single voice (VCED, already unpacked)
        uint8_t v[VOICE_SIZE];
        std::memcpy(v, d + 6, 155);
        v[155] = 0x3F;
        for (int i = 0; i < VOICE_SIZE; i++) {
            v[i] = std::min<int>(v[i], param_max(i));
        }
        cart.assign(v, v + VOICE_SIZE);
        names.push_back(voice_name_of(v));
        size = 0;
    }
    if (size >= 4096) {
        for (int i = 0; i < 32; i++) {
            uint8_t v[VOICE_SIZE];
            unpack_voice(d + i * 128, v);
            cart.insert(cart.end(), v, v + VOICE_SIZE);
            names.push_back(voice_name_of(v));
        }
    }
    if (cart.empty()) {
        UtilityFunctions::push_error("DexedSynth: not a DX7 voice or 32-voice bank (", data.size(), " bytes)");
        return 0;
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        cartridge_ = cart;
        names_ = names;
    }
    set_program(0);
    return int(names.size());
}

PackedStringArray DexedSynth::get_program_names() const {
    std::lock_guard<std::mutex> lock(mutex_);
    PackedStringArray out;
    for (const String &n : names_) {
        out.push_back(n);
    }
    return out;
}

void DexedSynth::set_program(int index) {
    std::lock_guard<std::mutex> lock(mutex_);
    int count = int(names_.size());
    if (count == 0) {
        return;
    }
    program_ = std::clamp(index, 0, count - 1);
    std::memcpy(voice_, cartridge_.data() + program_ * VOICE_SIZE, VOICE_SIZE);
    apply_voice_change();
}

int DexedSynth::get_program() const { return program_; }

String DexedSynth::get_voice_name() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return voice_name_of(voice_);
}

void DexedSynth::set_voice_name(const String &name) {
    std::lock_guard<std::mutex> lock(mutex_);
    CharString c = name.ascii();
    for (int i = 0; i < 10; i++) {
        voice_[145 + i] = i < c.length() ? uint8_t(c[i]) & 0x7F : ' ';
    }
}

// Called with the mutex held.
void DexedSynth::apply_voice_change() {
    if (!engine_ready_) {
        return;
    }
    lfo_.reset(voice_ + 137);
    for (Voice &v : voices_) {
        if (v.keydown || v.note->isPlaying()) {
            v.note->update(voice_, v.midinote, v.velocity, 1);
        }
    }
}

// ------------------------------------------------------------------ parameters
int DexedSynth::param_index(int op, const String &name) const {
    if (op < 1 || op > 6) {
        return -1;
    }
    for (int i = 0; i < 21; i++) {
        if (name == OP_NAMES[i]) {
            return (6 - op) * 21 + i;
        }
    }
    return -1;
}

int DexedSynth::global_index(const String &name) const {
    for (const GlobalParam &g : GLOBALS) {
        if (name == g.name) {
            return g.index;
        }
    }
    return -1;
}

void DexedSynth::set_op_param(int op, const String &name, int value) {
    if (name == "enabled") {
        if (op < 1 || op > 6) {
            return;
        }
        std::lock_guard<std::mutex> lock(mutex_);
        int bit = 1 << (6 - op);      // bit 5 = OP1 ... bit 0 = OP6
        voice_[155] = value ? (voice_[155] | bit) : (voice_[155] & ~bit);
        apply_voice_change();
        return;
    }
    int i = param_index(op, name);
    if (i < 0) {
        UtilityFunctions::push_error("DexedSynth: unknown operator parameter '", name, "' (op ", op, ")");
        return;
    }
    set_raw_param(i, value);
}

int DexedSynth::get_op_param(int op, const String &name) const {
    if (name == "enabled") {
        if (op < 1 || op > 6) {
            return 0;
        }
        return (voice_[155] >> (6 - op)) & 1;
    }
    int i = param_index(op, name);
    return i < 0 ? -1 : get_raw_param(i);
}

void DexedSynth::set_global_param(const String &name, int value) {
    int i = global_index(name);
    if (i < 0) {
        UtilityFunctions::push_error("DexedSynth: unknown parameter '", name, "'");
        return;
    }
    if (i == 134) {
        value -= 1;     // algorithm is 1..32 to the user
    }
    set_raw_param(i, value);
}

int DexedSynth::get_global_param(const String &name) const {
    int i = global_index(name);
    if (i < 0) {
        return -1;
    }
    int v = get_raw_param(i);
    return i == 134 ? v + 1 : v;
}

void DexedSynth::set_raw_param(int index, int value) {
    if (index < 0 || index >= VOICE_SIZE) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    voice_[index] = uint8_t(std::clamp(value, 0, param_max(index)));
    apply_voice_change();
}

int DexedSynth::get_raw_param(int index) const {
    if (index < 0 || index >= VOICE_SIZE) {
        return -1;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    return voice_[index];
}

PackedByteArray DexedSynth::get_voice_data() const {
    std::lock_guard<std::mutex> lock(mutex_);
    PackedByteArray out;
    out.resize(VOICE_SIZE);
    std::memcpy(out.ptrw(), voice_, VOICE_SIZE);
    return out;
}

void DexedSynth::set_voice_data(const PackedByteArray &data) {
    if (data.size() < 155) {
        return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    std::memcpy(voice_, data.ptr(), std::min<int64_t>(data.size(), VOICE_SIZE));
    if (data.size() < VOICE_SIZE) {
        voice_[155] = 0x3F;
    }
    for (int i = 0; i < VOICE_SIZE; i++) {
        voice_[i] = std::min<int>(voice_[i], param_max(i));
    }
    apply_voice_change();
}

PackedByteArray DexedSynth::export_voice_sysex() const {
    std::lock_guard<std::mutex> lock(mutex_);
    PackedByteArray out;
    const uint8_t head[6] = { 0xF0, 0x43, 0x00, 0x00, 0x01, 0x1B };
    for (uint8_t b : head) {
        out.push_back(b);
    }
    int sum = 0;
    for (int i = 0; i < 155; i++) {
        out.push_back(voice_[i]);
        sum += voice_[i];
    }
    out.push_back(uint8_t((128 - (sum & 0x7F)) & 0x7F));
    out.push_back(0xF7);
    return out;
}

// ------------------------------------------------------------------ settings
void DexedSynth::set_volume(float v) { volume_ = std::max(0.0f, v); }
float DexedSynth::get_volume() const { return volume_; }

void DexedSynth::set_polyphony(int n) {
    std::lock_guard<std::mutex> lock(mutex_);
    polyphony_ = std::clamp(n, 1, MAX_POLYPHONY);
}
int DexedSynth::get_polyphony() const { return polyphony_; }

void DexedSynth::set_pitch_bend(float amount) {
    std::lock_guard<std::mutex> lock(mutex_);
    controllers_.pitch_cc = std::clamp(int(0x2000 + amount * 0x2000), 0, 0x3FFF);
}

void DexedSynth::set_mod_wheel(int value) {
    std::lock_guard<std::mutex> lock(mutex_);
    controllers_.modwheel_cc = std::clamp(value, 0, 127);
    controllers_.refresh();
}

String DexedSynth::get_cartridge_path() const { return cartridge_path_; }

void DexedSynth::set_cartridge_path(const String &path) {
    cartridge_path_ = path;
    if (!path.is_empty() && FileAccess::file_exists(path)) {
        load_cartridge(path);
    }
}

// ------------------------------------------------------------------ AudioStream
Ref<AudioStreamPlayback> DexedSynth::_instantiate_playback() const {
    Ref<DexedSynthPlayback> p;
    p.instantiate();
    p->stream = Ref<DexedSynth>(const_cast<DexedSynth *>(this));
    return p;
}

String DexedSynth::_get_stream_name() const { return "DexedSynth"; }
double DexedSynth::_get_length() const { return 0.0; }
bool DexedSynth::_is_monophonic() const { return true; }

void DexedSynth::_bind_methods() {
    ClassDB::bind_method(D_METHOD("note_on", "note", "velocity"), &DexedSynth::note_on, DEFVAL(100));
    ClassDB::bind_method(D_METHOD("note_off", "note"), &DexedSynth::note_off);
    ClassDB::bind_method(D_METHOD("all_notes_off"), &DexedSynth::all_notes_off);
    ClassDB::bind_method(D_METHOD("load_cartridge", "path"), &DexedSynth::load_cartridge);
    ClassDB::bind_method(D_METHOD("load_cartridge_data", "data"), &DexedSynth::load_cartridge_data);
    ClassDB::bind_method(D_METHOD("get_program_names"), &DexedSynth::get_program_names);
    ClassDB::bind_method(D_METHOD("set_program", "index"), &DexedSynth::set_program);
    ClassDB::bind_method(D_METHOD("get_program"), &DexedSynth::get_program);
    ClassDB::bind_method(D_METHOD("get_voice_name"), &DexedSynth::get_voice_name);
    ClassDB::bind_method(D_METHOD("set_voice_name", "name"), &DexedSynth::set_voice_name);
    ClassDB::bind_method(D_METHOD("set_op_param", "op", "name", "value"), &DexedSynth::set_op_param);
    ClassDB::bind_method(D_METHOD("get_op_param", "op", "name"), &DexedSynth::get_op_param);
    ClassDB::bind_method(D_METHOD("set_global_param", "name", "value"), &DexedSynth::set_global_param);
    ClassDB::bind_method(D_METHOD("get_global_param", "name"), &DexedSynth::get_global_param);
    ClassDB::bind_method(D_METHOD("set_raw_param", "index", "value"), &DexedSynth::set_raw_param);
    ClassDB::bind_method(D_METHOD("get_raw_param", "index"), &DexedSynth::get_raw_param);
    ClassDB::bind_method(D_METHOD("get_voice_data"), &DexedSynth::get_voice_data);
    ClassDB::bind_method(D_METHOD("set_voice_data", "data"), &DexedSynth::set_voice_data);
    ClassDB::bind_method(D_METHOD("export_voice_sysex"), &DexedSynth::export_voice_sysex);
    ClassDB::bind_method(D_METHOD("set_volume", "volume"), &DexedSynth::set_volume);
    ClassDB::bind_method(D_METHOD("get_volume"), &DexedSynth::get_volume);
    ClassDB::bind_method(D_METHOD("set_polyphony", "voices"), &DexedSynth::set_polyphony);
    ClassDB::bind_method(D_METHOD("get_polyphony"), &DexedSynth::get_polyphony);
    ClassDB::bind_method(D_METHOD("set_pitch_bend", "amount"), &DexedSynth::set_pitch_bend);
    ClassDB::bind_method(D_METHOD("set_mod_wheel", "value"), &DexedSynth::set_mod_wheel);
    ClassDB::bind_method(D_METHOD("set_cartridge_path", "path"), &DexedSynth::set_cartridge_path);
    ClassDB::bind_method(D_METHOD("get_cartridge_path"), &DexedSynth::get_cartridge_path);

    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "volume", PROPERTY_HINT_RANGE, "0,2,0.01"), "set_volume", "get_volume");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "polyphony", PROPERTY_HINT_RANGE, "1,32,1"), "set_polyphony", "get_polyphony");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "cartridge_path", PROPERTY_HINT_FILE, "*.syx"), "set_cartridge_path", "get_cartridge_path");
}

// ------------------------------------------------------------------ playback
void DexedSynthPlayback::_start(double) { active = true; position = 0.0; }
void DexedSynthPlayback::_stop() { active = false; }
bool DexedSynthPlayback::_is_playing() const { return active; }
int32_t DexedSynthPlayback::_get_loop_count() const { return 0; }
double DexedSynthPlayback::_get_playback_position() const { return position; }
void DexedSynthPlayback::_seek(double) {}

int32_t DexedSynthPlayback::_mix(AudioFrame *buffer, float, int32_t frames) {
    if (!active || stream.is_null()) {
        for (int i = 0; i < frames; i++) {
            buffer[i].left = buffer[i].right = 0.0f;
        }
        return frames;
    }
    if (int(mono.size()) < frames) {
        mono.resize(frames);
    }
    stream->render(mono.data(), frames);
    for (int i = 0; i < frames; i++) {
        buffer[i].left = buffer[i].right = mono[i];
    }
    position += double(frames) / AudioServer::get_singleton()->get_mix_rate();
    return frames;
}
