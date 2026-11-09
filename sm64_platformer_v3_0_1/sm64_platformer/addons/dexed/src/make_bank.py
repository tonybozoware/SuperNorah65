# Builds biryani64.syx, a 32-voice DX7 bank of original starter voices (Biryani64).
import sys

def op(rates, levels, out, coarse=1, fine=0, detune=7, mode=0, bp=39, ld=0, rd=0, lc=0, rc=0, rs=0, ams=0, kvs=2):
    return dict(rates=rates, levels=levels, out=out, coarse=coarse, fine=fine, detune=detune, mode=mode,
                bp=bp, ld=ld, rd=rd, lc=lc, rc=rc, rs=rs, ams=ams, kvs=kvs)

OFF = op([99, 99, 99, 99], [99, 99, 99, 0], 0)

def voice(name, ops, alg, fb=0, sync=1, lfo=(35, 0, 0, 0, 1, 0), pms=3, transpose=24,
          prates=(99, 99, 99, 99), plevels=(50, 50, 50, 50)):
    # ops: dict op_number(1..6) -> op(); missing ops are silent
    p = bytearray(128)
    for i, n in enumerate([6, 5, 4, 3, 2, 1]):          # packed order is OP6 first
        o = ops.get(n, OFF)
        b = i * 17
        p[b:b + 4] = bytes(o['rates']); p[b + 4:b + 8] = bytes(o['levels'])
        p[b + 8], p[b + 9], p[b + 10] = o['bp'], o['ld'], o['rd']
        p[b + 11] = (o['rc'] << 2) | o['lc']
        p[b + 12] = (o['detune'] << 3) | o['rs']
        p[b + 13] = (o['kvs'] << 2) | o['ams']
        p[b + 14] = o['out']
        p[b + 15] = (o['coarse'] << 1) | o['mode']
        p[b + 16] = o['fine']
    p[102:106] = bytes(prates); p[106:110] = bytes(plevels)
    p[110] = alg - 1
    p[111] = (sync << 3) | fb
    sp, dl, pmd, amd, ls, wave = lfo
    p[112], p[113], p[114], p[115] = sp, dl, pmd, amd
    p[116] = (pms << 4) | (wave << 1) | ls
    p[117] = transpose
    p[118:128] = name.ljust(10)[:10].encode('ascii')
    return bytes(p)

voices = [
    voice("SOFT EP", {
        1: op([96, 25, 25, 67], [99, 75, 0, 0], 99, kvs=3),
        2: op([95, 50, 35, 78], [99, 0, 0, 0], 58, coarse=14, kvs=5),
        3: op([95, 20, 20, 50], [99, 90, 0, 0], 85, detune=8, kvs=2),
        4: op([95, 29, 20, 50], [99, 95, 0, 0], 72, coarse=1, kvs=4),
    }, alg=5, lfo=(30, 0, 5, 0, 1, 0), pms=2),
    voice("FM BASS", {
        1: op([99, 40, 30, 60], [99, 85, 70, 0], 99, coarse=1, kvs=2),
        2: op([99, 55, 40, 70], [99, 60, 40, 0], 78, coarse=1, kvs=4),
        3: op([99, 45, 30, 60], [99, 80, 60, 0], 70, coarse=1, detune=9),
        4: op([99, 60, 40, 70], [99, 50, 30, 0], 66, coarse=2),
    }, alg=5, fb=4),
    voice("GLASS BELL", {
        1: op([99, 22, 15, 30], [99, 60, 0, 0], 99, kvs=2),
        2: op([99, 30, 20, 35], [99, 50, 0, 0], 74, coarse=3, fine=50, kvs=3),
        3: op([99, 18, 12, 30], [99, 55, 0, 0], 80, coarse=2, detune=10),
        4: op([99, 25, 18, 35], [99, 40, 0, 0], 68, coarse=7, kvs=3),
    }, alg=5),
    voice("SINE", {
        1: op([99, 99, 99, 70], [99, 99, 99, 0], 99, kvs=1),
    }, alg=1),
]
while len(voices) < 32:
    voices.append(voice("INIT VOICE", {1: op([99, 99, 99, 99], [99, 99, 99, 0], 99, kvs=0)}, alg=1))

data = b"".join(voices)
checksum = (128 - (sum(data) & 0x7F)) & 0x7F
syx = bytes([0xF0, 0x43, 0x00, 0x09, 0x20, 0x00]) + data + bytes([checksum, 0xF7])
open(sys.argv[1], "wb").write(syx)
print(len(syx), "bytes")
