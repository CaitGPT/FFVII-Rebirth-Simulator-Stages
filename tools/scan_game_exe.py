"""Run the native helpers' code searches on a game executable file, offline, and print what each would find.

    python -I tools/scan_game_exe.py <path to ff7rebirth_.exe> [name]

For a game version we have not measured (Steam 1.005, 2026-11-23). It repeats, on the file:
  - Simulator Stages' level helper (native/src/main.cpp): the build table check (FlushLoading reads the loader's TLS
    slot), the pattern search a build outside the table uses, and the package loader's four addresses;
  - Simulator Upgrade's Custom Training helper (native/custom-training/src/dllmain.cpp): GetDifficulty by its code.
It prints a table row ready for LoaderTlsBuilds and Loader::Builds when everything is found and unique.
Reads the file only. The image is laid out as the loader would, at the preferred base, without relocations: a
pointer in the file holds 0x140000000 + its target's RVA, which is what the vtable search looks for.
"""
import hashlib
import struct
import sys

IMAGE_BASE = 0x140000000
FLUSH = "48 89 5C 24 08 48 89 6C 24 10 56 57 41 56 B8 40 00 00 00 E8 ?? ?? ?? ?? 48 2B E0 C5 F8 29 74 24 30 8B FA"
IS_LOADING = "33 D2 33 C0 F0 0F B1 91 08 02 00 00 75 0C 33 C0 F0 0F B1 91 0C 02 00 00 74 02 B2 01 8A C2 C3"
CREATOR = "40 53 B8 20 00 00 00 E8 ?? ?? ?? ?? 48 2B E0 48 83 3D ?? ?? ?? ?? 00 74 ?? E8 ?? ?? ?? ?? 48 8B C8"
GET_DIFFICULTY = ("48 8B 05 ?? ?? ?? ?? 48 85 C0 74 ?? 84 C9 75 ?? 38 88 CA 0B 00 00 75 ?? 48 8B 80 00 01 00 00 48 8B 40"
                  " 28 48 83 C0 10 74 ?? 80 3D ?? ?? ?? ?? 00 75 ?? 8A 40 20 C3 8A 80 C9 0B 00 00 C3 B0 02 C3 B0 01 C3")
KNOWN = {  # name: (flushLoading, slot) RVAs, and Loader (global, vtable, isLoading, creator) VAs, from main.cpp
    "steam-2025-01": ((0x872A58, 0x870E42C), (0x149145D30, 0x145DE95E0, 0x140872DEC, 0x14467796C)),
    "epic-1.005": ((0x795590, 0x8640BBC), (0x14907BEB0, 0x145D23438, 0x1407956F8, 0x1444D3D98)),
}


class Image:
    def __init__(self, data):
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        assert data[pe:pe + 4] == b"PE\0\0", "not a PE file"
        sections = struct.unpack_from("<H", data, pe + 6)[0]
        optional = pe + 24
        optional_size = struct.unpack_from("<H", data, pe + 20)[0]
        self.base = struct.unpack_from("<Q", data, optional + 24)[0]
        size = struct.unpack_from("<I", data, optional + 56)[0]
        self.pdata = struct.unpack_from("<II", data, optional + 112 + 3 * 8)   # IMAGE_DIRECTORY_ENTRY_EXCEPTION
        self.mem = bytearray(size)
        self.sections = []
        at = optional + optional_size
        for i in range(sections):
            name = data[at:at + 8].rstrip(b"\0").decode("ascii", "replace")
            vsize, rva, raw_size, raw_at = struct.unpack_from("<IIII", data, at + 8)
            flags = struct.unpack_from("<I", data, at + 36)[0]
            n = min(raw_size, vsize)
            self.mem[rva:rva + n] = data[raw_at:raw_at + n]
            self.sections.append((name, rva, vsize, flags))
            at += 40
        self.text = next((rva, vsize) for name, rva, vsize, _ in self.sections if name == ".text")

    @staticmethod
    def parse(pattern):
        return [None if t.startswith("?") else int(t, 16) for t in pattern.split()]

    def all_in(self, pattern, start, size):
        want = self.parse(pattern)
        fixed = max((i for i, b in enumerate(want) if b is not None), key=lambda i: 0)
        head = bytes(want[:next((i for i, b in enumerate(want) if b is None), len(want))])
        out, mem, end = [], self.mem, start + size - len(want)
        i = mem.find(head, start, start + size)
        while 0 <= i <= end:
            if all(b is None or mem[i + k] == b for k, b in enumerate(want)):
                out.append(i)
            i = mem.find(head, i + 1, start + size)
        return out

    def unique_in_text(self, pattern):
        hits = self.all_in(pattern, *self.text)
        return (hits[0] if len(hits) == 1 else 0), len(hits)

    def unique_in_code(self, pattern):  # Custom Training searches every executable section
        hits = []
        for name, rva, vsize, flags in self.sections:
            if flags & 0x20000000:
                hits += self.all_in(pattern, rva, vsize)
        return (hits[0] if len(hits) == 1 else 0), len(hits)

    def function_of(self, rva):
        at, size = self.pdata
        low, high = 0, size // 12
        while low < high:
            mid = (low + high) // 2
            if struct.unpack_from("<I", self.mem, at + mid * 12)[0] <= rva:
                low = mid + 1
            else:
                high = mid
        if not low:
            return 0
        begin, end = struct.unpack_from("<II", self.mem, at + (low - 1) * 12)[:2]
        return begin if begin <= rva < end else 0

    def rip(self, rva, disp_at, length):
        return rva + length + struct.unpack_from("<i", self.mem, rva + disp_at)[0]

    def reads_loader_slot(self, fn, want):
        m = self.mem
        return m[fn + 0xAC] == 0x8B and m[fn + 0xAD] == 0x0D and self.rip(fn + 0xAC, 2, 6) == want

    def qwords_equal(self, value):
        needle, out = struct.pack("<Q", value), []
        for name, rva, vsize, flags in self.sections:
            if flags & 0x40000000:   # readable
                i = self.mem.find(needle, rva, rva + vsize)
                while i >= 0:
                    out.append(i)
                    i = self.mem.find(needle, i + 1, rva + vsize)
        return out

    def matches(self, va, pattern):
        rva = va - IMAGE_BASE
        return all(b is None or self.mem[rva + k] == b for k, b in enumerate(self.parse(pattern)))


def main():
    path = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else "this-build"
    data = open(path, "rb").read()
    print(f"{path}\n  {len(data):,} bytes, SHA-256 {hashlib.sha256(data).hexdigest().upper()}")
    img = Image(data)
    print(f"  preferred base {img.base:#x}; .text at {img.text[0]:#x}, {img.text[1]:,} bytes")
    entropy_hint = sum(1 for b in img.mem[img.text[0]:img.text[0] + 65536] if b == 0) / 65536
    print(f"  zero bytes in the first 64 KB of .text: {entropy_hint:.1%} (near 0% suggests packed or encrypted code)")

    print("Stages level helper:")
    for name, ((flush, slot), _) in KNOWN.items():
        print(f"  table entry {name}: {'MATCHES' if img.reads_loader_slot(flush, slot) else 'no'}")
    flush_hit, n = img.unique_in_text(FLUSH)
    flush = img.function_of(flush_hit) if flush_hit else 0
    slot = img.rip(flush + 0xAC, 2, 6) if flush else 0
    ok_slot = bool(flush) and img.reads_loader_slot(flush, slot)
    print(f"  FlushLoading pattern: {n} match(es); function {flush:#x}; reads TLS slot at {slot:#x}: {ok_slot}")

    is_loading, n1 = img.unique_in_text(IS_LOADING)
    creator_hit, n2 = img.unique_in_text(CREATOR)
    creator = img.function_of(creator_hit) if creator_hit else 0
    print(f"  IsLoadingPackages: {n1} match(es) at {is_loading:#x}; loader creator: {n2} match(es), function {creator:#x}")
    loads = stores = vtable = 0
    if is_loading and creator:
        loads, stores = img.rip(creator + 0x55, 3, 7), img.rip(creator + 0x67, 3, 7)
        slots = img.qwords_equal(IMAGE_BASE + is_loading)
        print(f"  creator loads {loads:#x}, stores {stores:#x} ({'same' if loads == stores else 'DIFFERENT'});"
              f" pointers to IsLoadingPackages: {[hex(s) for s in slots]}")
        if len(slots) == 1 and slots[0] >= 17 * 8:
            vtable = slots[0] - 17 * 8
    va = lambda rva: IMAGE_BASE + rva
    verified = bool(vtable) and loads == stores and img.matches(va(is_loading), IS_LOADING) \
        and img.matches(va(creator + 0x55), "48 8B 0D") and img.matches(va(creator + 0x67), "48 89 15")
    print(f"  loader verified as the helper checks it: {verified}")
    if ok_slot and verified:
        print("  table rows:")
        print(f'    {{"{label}",{flush:#x},{slot:#x}}},')
        print(f"    {{{va(loads):#x},{va(vtable):#x},{va(is_loading):#x},{va(creator):#x}}},   // {label}")

    print("Custom Training (Simulator Upgrade):")
    hit, n = img.unique_in_code(GET_DIFFICULTY)
    if hit:
        print(f"  GetDifficulty: unique at {hit:#x}; difficulty global at {img.rip(hit, 3, 7):#x}")
    else:
        print(f"  GetDifficulty: {n} match(es): the helper would switch itself off")


if __name__ == "__main__":
    main()
