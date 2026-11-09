// Registers DexedSynth with Godot. Written for Biryani64.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "dexed_synth.h"

using namespace godot;

void initialize_dexed(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(DexedSynth);
    GDREGISTER_CLASS(DexedSynthPlayback);
}

void uninitialize_dexed(ModuleInitializationLevel) {}

extern "C" {
GDExtensionBool GDE_EXPORT dexed_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
        const GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init_obj(get_proc_address, library, initialization);
    init_obj.register_initializer(initialize_dexed);
    init_obj.register_terminator(uninitialize_dexed);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
