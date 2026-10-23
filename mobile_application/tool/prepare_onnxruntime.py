"""Prepares ONNX Runtime's Java layer so it can share ONE native runtime with the speech library (sherpa_onnx).

Why this exists
---------------
The on-phone face reading uses ONNX Runtime from Java/Kotlin (the Maven library `onnxruntime-android`), and the on-phone speech
reading uses sherpa_onnx, which ships its OWN libonnxruntime.so. The two native libraries use versioned symbols:

    sherpa_onnx's libonnxruntime.so and libsherpa-onnx-c-api.so  -> VERS_1.28.2
    onnxruntime-android's libonnxruntime.so and its JNI bridge     -> VERS_1.28.0

Android's linker matches those tags exactly, so each side works only with its own copy ("cannot locate symbol OrtGetApiBase")
and the two cannot be mixed. Shipping both copies under the same name is impossible, and picking one breaks the other side.

What this script does
---------------------
It takes the Java classes (classes.jar) and the four JNI bridges (libonnxruntime4j_jni.so for arm64-v8a, armeabi-v7a, x86,
x86_64) out of the Maven library, and rewrites the one version tag the JNI bridge asks for from VERS_1.28.0 to VERS_1.28.2 (same
length, plus its ELF hash), so the bridge links against the speech library's runtime. The C interface of 1.28.0 and 1.28.2 is
the same. The Maven library itself is then NOT used (its own libonnxruntime.so would clash again).

Outputs (committed, small):
    android/app/libs/onnxruntime-android-<version>-classes.jar
    android/app/src/main/jniLibs/<abi>/libonnxruntime4j_jni.so      (patched)

Run again when the versions change:
    python tool/prepare_onnxruntime.py --aar <path to onnxruntime-android-1.28.0.aar> --old VERS_1.28.0 --new VERS_1.28.2
    python tool/prepare_onnxruntime.py --verify        # prints the tags the committed files ask for
"""
import argparse
import glob
import os
import struct
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(HERE, "..", "android", "app"))
ABIS = ["arm64-v8a", "armeabi-v7a", "x86", "x86_64"]
SHT_GNU_VERNEED = 0x6FFFFFFE


def elf_hash(name: bytes) -> int:
    h = 0
    for c in name:
        h = ((h << 4) + c) & 0xFFFFFFFF
        g = h & 0xF0000000
        if g:
            h ^= g >> 24
        h &= ~g & 0xFFFFFFFF
    return h


def _sections(data):
    is64 = data[4] == 2
    if is64:
        shoff = struct.unpack_from("<Q", data, 0x28)[0]
        shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
        fmt = "<IIQQQQIIQQ"
    else:
        shoff = struct.unpack_from("<I", data, 0x20)[0]
        shentsize, shnum = struct.unpack_from("<HH", data, 0x2E)
        fmt = "<IIIIIIIIII"
    secs = []
    for i in range(shnum):
        f = struct.unpack_from(fmt, data, shoff + i * shentsize)
        secs.append(dict(type=f[1], off=f[4], size=f[5], link=f[6], info=f[7]))
    return secs


def _cstr(data, off):
    return bytes(data[off:data.index(b"\0", off)])


def version_requirements(data):
    """[(file, [(name, hash_offset, name_offset)])] from .gnu.version_r."""
    secs = _sections(data)
    need = next((s for s in secs if s["type"] == SHT_GNU_VERNEED), None)
    if need is None:
        return []
    dynstr = secs[need["link"]]
    out, pos = [], need["off"]
    for _ in range(need["info"]):
        vn_version, vn_cnt, vn_file, vn_aux, vn_next = struct.unpack_from("<HHIII", data, pos)
        auxes, aux = [], pos + vn_aux
        for _ in range(vn_cnt):
            vna_hash, vna_flags, vna_other, vna_name, vna_next = struct.unpack_from("<IHHII", data, aux)
            auxes.append((_cstr(data, dynstr["off"] + vna_name), aux, dynstr["off"] + vna_name))
            aux += vna_next
        out.append((_cstr(data, dynstr["off"] + vn_file), auxes))
        pos += vn_next
    return out


def patch_tag(data: bytearray, old: bytes, new: bytes) -> int:
    assert len(old) == len(new), "the new tag must have the same length as the old one"
    done = 0
    for _file, auxes in version_requirements(data):
        for name, hash_at, name_at in auxes:
            if name == old:
                struct.pack_into("<I", data, hash_at, elf_hash(new))
                data[name_at:name_at + len(new)] = new
                done += 1
    return done


def find_aar():
    hits = glob.glob(os.path.expanduser("~/.gradle/caches/modules-2/files-2.1/com.microsoft.onnxruntime/onnxruntime-android/*/*/*.aar"))
    return sorted(hits)[-1] if hits else None


def verify():
    for abi in ABIS:
        p = os.path.join(APP, "src", "main", "jniLibs", abi, "libonnxruntime4j_jni.so")
        if not os.path.exists(p):
            print(f"{abi}: MISSING {p}")
            continue
        data = bytearray(open(p, "rb").read())
        tags = sorted({name.decode() for _f, auxes in version_requirements(data) for name, _h, _n in auxes if name.startswith(b"VERS_")})
        print(f"{abi}: asks for {tags}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--aar")
    ap.add_argument("--old", default="VERS_1.28.0")
    ap.add_argument("--new", default="VERS_1.28.2")
    ap.add_argument("--verify", action="store_true")
    a = ap.parse_args()
    if a.verify:
        return verify()
    aar = a.aar or find_aar()
    if not aar:
        sys.exit("Pass --aar <path to onnxruntime-android-x.y.z.aar> (it is in the Gradle cache after a build).")
    version = os.path.basename(aar).replace("onnxruntime-android-", "").replace(".aar", "")
    os.makedirs(os.path.join(APP, "libs"), exist_ok=True)
    with zipfile.ZipFile(aar) as z:
        jar = os.path.join(APP, "libs", f"onnxruntime-android-{version}-classes.jar")
        open(jar, "wb").write(z.read("classes.jar"))
        print("wrote", os.path.relpath(jar, APP), os.path.getsize(jar), "bytes")
        for abi in ABIS:
            data = bytearray(z.read(f"jni/{abi}/libonnxruntime4j_jni.so"))
            n = patch_tag(data, a.old.encode(), a.new.encode())
            if n != 1:
                sys.exit(f"{abi}: expected exactly one '{a.old}' requirement, found {n}")
            out = os.path.join(APP, "src", "main", "jniLibs", abi)
            os.makedirs(out, exist_ok=True)
            open(os.path.join(out, "libonnxruntime4j_jni.so"), "wb").write(data)
            print(f"wrote {abi}/libonnxruntime4j_jni.so ({len(data)} bytes): {a.old} -> {a.new}")
    verify()


if __name__ == "__main__":
    main()
