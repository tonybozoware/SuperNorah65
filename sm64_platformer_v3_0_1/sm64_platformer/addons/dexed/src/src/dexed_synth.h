// DexedSynth: a DX7-style FM synth for Godot, built on the msfa engine from
// Dexed (Apache License 2.0, see msfa/LICENSE-Apache-2.0.txt). Written for
// Biryani64.
//
// Use it as the stream of an AudioStreamPlayer, start the player, then call
// note_on / note_off and the parameter methods on the stream.
#pragma once

#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>
#include <mutex>
#include <vector>
#include <cstdint>

#include "msfa/controllers.h"
#include "msfa/dx7note.h"
#include "msfa/fm_core.h"
#include "msfa/lfo.h"

namespace godot {

class DexedSynth : public AudioStream {
    GDCLASS(DexedSynth, AudioStream)

public:
    static const int VOICE_SIZE = 156;   // unpacked DX7 voice (VCED + op on/off)
    static const int MAX_POLYPHONY = 32;

    DexedSynth();
    ~DexedSynth();

    // Notes
    void note_on(int note, int velocity);
    void note_off(int note);
    void all_notes_off();

    // Cartridges / programs
    int load_cartridge(const String &path);              // .syx (32-voice bank or single voice)
    int load_cartridge_data(const PackedByteArray &data);
    PackedStringArray get_program_names() const;
    void set_program(int index);
    int get_program() const;
    String get_voice_name() const;
    void set_voice_name(const String &name);

    // Parameters
    // op: 1..6. name: rate1..rate4, level1..level4, break_point, left_depth,
    // right_depth, left_curve, right_curve, rate_scaling, amp_mod_sens,
    // velocity_sens, output_level, mode, coarse, fine, detune, enabled
    void set_op_param(int op, const String &name, int value);
    int get_op_param(int op, const String &name) const;
    // name: algorithm (1..32), feedback, osc_sync, lfo_speed, lfo_delay,
    // lfo_pitch_depth, lfo_amp_depth, lfo_sync, lfo_wave, lfo_pitch_sens,
    // transpose, pitch_rate1..4, pitch_level1..4
    void set_global_param(const String &name, int value);
    int get_global_param(const String &name) const;
    void set_raw_param(int index, int value);            // 0..155, DX7 VCED order
    int get_raw_param(int index) const;
    PackedByteArray get_voice_data() const;              // 156 bytes, for saving
    void set_voice_data(const PackedByteArray &data);
    PackedByteArray export_voice_sysex() const;          // single-voice .syx

    // Settings
    void set_volume(float v);
    float get_volume() const;
    void set_polyphony(int n);
    int get_polyphony() const;
    void set_pitch_bend(float semitones_fraction);       // -1..1 of the bend range
    void set_mod_wheel(int value);                       // 0..127
    String get_cartridge_path() const;
    void set_cartridge_path(const String &path);

    // Audio (called from the playback, on the audio thread)
    void render(float *out, int frames);

    // AudioStream
    Ref<AudioStreamPlayback> _instantiate_playback() const override;
    String _get_stream_name() const override;
    double _get_length() const override;
    bool _is_monophonic() const override;

protected:
    static void _bind_methods();

private:
    struct Voice {
        std::unique_ptr<Dx7Note> note;
        int midinote = -1;
        int velocity = 0;
        bool keydown = false;
        uint64_t started = 0;
    };

    void ensure_engine();
    void apply_voice_change();          // after a parameter edit
    static void unpack_voice(const uint8_t *packed, uint8_t *out);
    static void init_voice(uint8_t *out);
    int param_index(int op, const String &name) const;
    int global_index(const String &name) const;
    static int param_max(int index);

    mutable std::mutex mutex_;
    bool engine_ready_ = false;
    double rate_ = 44100.0;
    std::shared_ptr<TuningState> tuning_;
    MTSClient mts_;
    FmCore core_;
    Controllers controllers_;
    Lfo lfo_;
    std::vector<Voice> voices_;
    int polyphony_ = 16;
    uint64_t note_counter_ = 0;

    std::vector<uint8_t> cartridge_;   // programs * VOICE_SIZE
    std::vector<String> names_;
    int program_ = 0;
    uint8_t voice_[VOICE_SIZE];

    float volume_ = 0.8f;
    String cartridge_path_;

    int32_t block_[N];
    float block_out_[N];
    int block_pos_ = N;
};

class DexedSynthPlayback : public AudioStreamPlayback {
    GDCLASS(DexedSynthPlayback, AudioStreamPlayback)

public:
    Ref<DexedSynth> stream;
    bool active = false;
    double position = 0.0;
    std::vector<float> mono;      // render buffer (a member, not thread_local: safe at DLL unload)

    void _start(double from_pos) override;
    void _stop() override;
    bool _is_playing() const override;
    int32_t _get_loop_count() const override;
    double _get_playback_position() const override;
    void _seek(double position) override;
    int32_t _mix(AudioFrame *buffer, float rate_scale, int32_t frames) override;

protected:
    static void _bind_methods() {}
};

} // namespace godot
