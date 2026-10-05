package game

BUILD_VERSION :: "0.15.0"
// Official build/bench scripts embed a source fingerprint. Direct Odin invocations
// remain possible; their recordings are explicitly labelled development.
// Quotes force -define to treat digit-leading hashes as strings. This Odin
// version preserves those quotes in #config, so remove them before recording.
BUILD_ID_OPTION :: #config(TOAD_BUILD_ID, "development")
BUILD_ID := BUILD_ID_OPTION[1:len(BUILD_ID_OPTION)-1] if len(BUILD_ID_OPTION) >= 2 && BUILD_ID_OPTION[0] == '"' && BUILD_ID_OPTION[len(BUILD_ID_OPTION)-1] == '"' else BUILD_ID_OPTION
#assert(len(BUILD_ID_OPTION) <= 66)
