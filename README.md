# toyskkserv

A toy SKK skkserv. Just made this for fun.

This is a rewritten of [toyskkserv-go](https://github.com/waynezhang/toyskkserv-go) in Zig.

## Features

- [x] Configurable dictionary via urls. `.gz`, `.tar.gz` are supported.
- [x] EUC-JIS-2004, UTF-8 dictionaries are supported.
- [x] Google Transliterate API

## Protocol

The following commands are supported:

- `0`: disconnect
- `1midashi `: request candidates
- `2`: get skkserv version
- `3`: get skkserv host
- `4midashi `: request completion

Some custom protocol for internal us:

- `5reload`: reload dictionaries without restart
- ...

## Install

### Build from source

`$ zig build -Doptimize=ReleaseSafe && cp ./zig-out/bin/toyskkserv /usr/local/bin`

### Via Homebrew

`$ brew tap waynezhang/homebrew-tap && brew install toyskkserv`

## Usage

A configuration file is required. toyskkserv tries to find `toyskkserv.zon` in the following order:

- `$HOME/.config`
- Current directory

Copy [the sample file](https://github.com/waynezhang/toyskkserv/blob/main/conf/toyskkserv.zon) to the directory and start running:

- `$ toyskkserv serve [-v]`
- Or `brew services start toyskkserv`

## All command

- `serve`: Start the server
- `update`: Update dictionaries from internet.
- `reload`: Tell the server to reload all dictionaries from disk
- `--help`: Show help

## Configuration

### Dictionary path

`.dictionary_directory = ""`: The directory where the dictionaries are downloaded to.

### Host, Port

`.listen_addr = "127.0.0.1:1178"`: The host and port that the server listens to. It's recommended to only listen to localhost.

### Google Input

`.fallback_to_google = true`: Enable the request to [Google Transliterate API](https://www.google.co.jp/ime/cgiapi.html).

If it's enabled, toyskkserv calls this API if there is no candidates found in local directionaries.

Plus, toyskkserv doesn't return any candidates if no candidates are found for exactly the original word segment to avoid the noise. For example, Goolge API returns the following response for `ここではきものをぬぐ`:

```
[
  ["ここでは",
    ["ここでは", "個々では", "此処では"],
  ],
  ["きものを",
    ["着物を", "きものを", "キモノを"],
  ],
  ["ぬぐ",
    ["脱ぐ", "ぬぐ", "ヌグ"],
  ],
]
```

Since there are no word segment for the original request `ここではきものをぬぐ`, no candidates will be returned. However, if the request word is `ここでは` and Google API returns the following response:

```
[
  [
    "ここでは",
    [
      "ここでは",
      "個々では",
      "此処では",
      "ココでは",
      "ココデは"
    ]
  ]
]
```

toyskkserv returns `/ここでは/個々では/此処では/ココでは/ココデは/` as response to SKK client.

### Dictionaries

```
.dictionaries = .{
    .{ .url = "https://skk-dev.github.io/dict/SKK-JISYO.L.gz" }, // 基本辞書
    .{
       .url = "https://skk-dev.github.io/dict/zipcode.tar.gz",
       .files = .{
         "zipcode/SKK-JISYO.zipcode",
         "zipcode/SKK-JISYO.office.zipcode",
       },
    },
    .{ .url = "~/skk-dict/some_dict_file" },
},
```

URL and local file paths are supported. toyskkserv downloads remote dictionaries to the folder that defined above. The local dictionaries are refered directly and not copied to anywhere.

