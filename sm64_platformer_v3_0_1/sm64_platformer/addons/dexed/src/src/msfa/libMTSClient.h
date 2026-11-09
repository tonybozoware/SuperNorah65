// Stand-in for the MTS-ESP client (written for Biryani64): microtuning masters
// are never present, so the voice code always uses its own tuning.
#ifndef BIRYANI_MTS_STUB_H
#define BIRYANI_MTS_STUB_H
struct MTSClient {};
inline bool MTS_HasMaster(const MTSClient *) { return false; }
inline double MTS_NoteToFrequency(const MTSClient *, char midinote, char) {
    return 440.0 * __builtin_pow(2.0, (midinote - 69) / 12.0);
}
#endif
