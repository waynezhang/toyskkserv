const std = @import("std");
const build_options = @import("build_options");

pub const FullDescription = build_options.name ++ " " ++ Version;
pub const Version = build_options.version ++ "+" ++ build_options.commit;
