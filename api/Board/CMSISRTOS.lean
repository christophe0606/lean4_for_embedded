module
prelude
public import Board.CMSISRTOS.LowLevel

namespace Board.CMSISRTOS
public section
abbrev EventFlagsId := LowLevel.EventFlagsId
abbrev Flags := LowLevel.Flags
abbrev Flags.single := LowLevel.Flags.single
abbrev Flags.ofUInt32? := LowLevel.Flags.ofUInt32?
namespace EventFlags
abbrev new := LowLevel.eventFlagsNew
abbrev set := LowLevel.eventFlagsSet
abbrev clear := LowLevel.eventFlagsClear
abbrev get := LowLevel.eventFlagsGet
abbrev wait := LowLevel.eventFlagsWait
abbrev delete := LowLevel.eventFlagsDelete
end EventFlags
end
end Board.CMSISRTOS
