from build.ab import simplerule
from build.llvm import llvmrawprogram
from tools.build import mkcpmfs
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    PASCAL_APPS,
    FORTH_APPS,
    Z65_APPS,
)

llvmrawprogram(
    name="bios",
    srcs=["./rp6502.S"],
    deps=["include", "src/lib+bioslib"],
    linkscript="./rp6502.ld",
)

simplerule(
    name="rom",
    ins=[".+bios", "src/bdos"],
    outs=["=CPM65.RP6"],
    deps=["scripts/mkrp6502rom.py"],
    commands=[
        "python3 $[deps[0]] $[ins[0]] 0xd000 $[ins[1]] 0xe800 $[outs[0]]"
    ],
    label="MKROM",
)

mkcpmfs(
    name="cpmfs",
    format="rp6502",
    items={"0:ccp.sys@sr": "src+ccp"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS
    | FORTH_APPS
    | Z65_APPS,
)
