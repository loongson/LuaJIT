----------------------------------------------------------------------------
-- LuaJIT LoongArch disassembler module.
--
-- Copyright (C) 2005-2026 Mike Pall. All rights reserved.
-- Copyright (C) 2026 Loongson Technology. All rights reserved.
-- Released under the MIT/X license. See Copyright Notice in luajit.h
----------------------------------------------------------------------------
-- This is a helper module used by the LuaJIT machine code dumper module.
--
-- It disassembles most LoongArch instructions.
-- NYI: SIMD instructions.
------------------------------------------------------------------------------

local type = type
local byte, format = string.byte, string.format
local match, gmatch = string.match, string.gmatch
local concat = table.concat
local bit = require("bit")
local band, bor, bnot, tohex = bit.band, bit.bor, bit.bnot, bit.tohex
local lshift, rshift, arshift = bit.lshift, bit.rshift, bit.arshift

------------------------------------------------------------------------------
-- Opcode maps
------------------------------------------------------------------------------

local map_zero_31_15 = { -- [31:15] = 0
  shift = 10, mask = 0xff,
  [4] = "clo.wDJ",
  [5] = "clz.wDJ",
  [6] = "cto.wDJ",
  [7] = "ctz.wDJ",
  [8] = "clo.dDJ",
  [9] = "clz.dDJ",
  [10] = "cto.dDJ",
  [11] = "ctz.dDJ",
  [12] = "revb.2hDJ",
  [13] = "revb.4hDJ",
  [14] = "revb.2wDJ",
  [15] = "revb.dDJ",
  [16] = "revh.2wDJ",
  [17] = "revh.dDJ",
  [18] = "bitrev.4bDJ",
  [19] = "bitrev.8bDJ",
  [20] = "bitrev.wDJ",
  [21] = "bitrev.dDJ",
  [22] = "ext.w.hDJ",
  [23] = "ext.w.bDJ",
}

local map_zero_31_20 = { -- [31:20] = 0
  shift = 18, mask = 0x3,
  [0] = map_zero_31_15,
  [1] = {
    shift = 17, mask = 0x1,
    [0] = "alsl.wDJKQ", "alsl.wuDJKQ",
  },
  [2] = "bytepick.wDJKQ",
  [3] = "bytepick.dDJKB",
}

local map_zero_31_22 = { -- [31:22] = 0
  shift = 20, mask = 0x3,
  [0] = map_zero_31_20,
  [1] = {
    shift = 15, mask = 0x1f,
    [0] = "add.wDJK",
    [1] = "add.dDJK",
    [2] = "sub.wDJK",
    [3] = "sub.dDJK",
    [4] = "sltDJK",
    [5] = "sltuDJK",
    [6] = "maskeqzDJK",
    [7] = "masknezDJK",
    [8] = "norDJK",
    [9] = "andDJK",
    [10] = "orDJK",
    [11] = "xorDJK",
    [12] = "ornDJK",
    [13] = "andnDJK",
    [14] = "sll.wDJK",
    [15] = "srl.wDJK",
    [16] = "sra.wDJK",
    [17] = "sll.dDJK",
    [18] = "srl.dDJK",
    [19] = "sra.dDJK",
    [22] = "rotr.wDJK",
    [23] = "rotr.dDJK",
    [24] = "mul.wDJK",
    [25] = "mulh.wDJK",
    [26] = "mulh.wuDJK",
    [27] = "mul.dDJK",
    [28] = "mulh.dDJK",
    [29] = "mulh.duDJK",
    [30] = "mulw.d.wDJK",
    [31] = "mulw.d.wuDJK",
  },
  [2] = {
    shift = 19, mask = 0x1,
    [0] = {
      shift = 15, mask = 0x1f,
      [0] = "div.wDJK",
      [1] = "mod.wDJK",
      [2] = "div.wuDJK",
      [3] = "mod.wuDJK",
      [4] = "div.dDJK",
      [5] = "mod.dDJK",
      [6] = "div.duDJK",
      [7] = "mod.duDJK",
    },
    [1] = {
      shift = 17, mask = 0x7,
      [6] = "alsl.dDJKQ",
    },
  },
}

local map_zero_31_23 = { -- [31:24] = 0
  shift = 22, mask = 0x3,
  [0] = map_zero_31_22,
  [1] = {
    shift = 21, mask = 0x1,
    [0] = {
      shift = 16, mask = 0x1,
      [0] = {
        shift = 15, mask = 0x1f,
        [1] = "slli.wDJU",
        [9] = "srli.wDJU",
        [17] = "srai.wDJU",
        [25] = "rotri.wDJU",
      },
      [1] = {
        shift = 16, mask = 0xf,
        [1] = "slli.dDJV",
        [5] = "srli.dDJV",
        [9] = "srai.dDJV",
        [13] = "rotri.dDJV",
      },
    },
    [1] = {
      shift = 15, mask = 0x1,
      [0] = "bstrins.wDJMU",
      [1] = "bstrpick.wDJMU",
    },
  },
  [2] = "bstrins.dDJNV",
  [3] = "bstrpick.dDJNV",
}


local map_zero_31_25 = { -- [31:25] = 0
  shift = 24, mask = 0x1,
  [0] = map_zero_31_23,
  [1] = {
    shift = 18, mask = 0x3f,
    [0] = {
      shift = 15, mask = 0x7,
      [1] = "fadd.sFGH",
      [2] = "fadd.dFGH",
      [5] = "fsub.sFGH",
      [6] = "fsub.dFGH",
    },
    [1] = {
      shift = 15, mask = 0x7,
      [1] = "fmul.sFGH",
      [2] = "fmul.dFGH",
      [5] = "fdiv.sFGH",
      [6] = "fdiv.dFGH",
    },
    [2] = {
      shift = 15, mask = 0x7,
      [1] = "fmax.sFGH",
      [2] = "fmax.dFGH",
      [5] = "fmin.sFGH",
      [6] = "fmin.dFGH",
    },
    [3] = {
      shift = 15, mask = 0x7,
      [1] = "fmaxa.sFGH",
      [2] = "fmaxa.dFGH",
      [5] = "fmina.sFGH",
      [6] = "fmina.dFGH",
    },
    [4] = {
      shift = 15, mask = 0x7,
      [1] = "fscaleb.sFGH",
      [2] = "fscaleb.dFGH",
      [5] = "fcopysign.sFGH",
      [6] = "fcopysign.dFGH",
    },
    [5] = {
      shift = 10, mask = 0xff,
      [1] = "fabs.sFG",
      [2] = "fabs.dFG",
      [5] = "fneg.sFG",
      [6] = "fneg.dFG",
      [9] = "flogb.sFG",
      [10] = "flogb.dFG",
      [13] = "fclass.sFG",
      [14] = "fclass.dFG",
      [17] = "fsqrt.sFG",
      [18] = "fsqrt.dFG",
      [21] = "frecip.sFG",
      [22] = "frecip.dFG",
      [25] = "frsqrt.sFG",
      [26] = "frsqrt.dFG",
      [29] = "frecipe.sFG",
      [30] = "frecipe.dFG",
      [33] = "frsqrte.sFG",
      [34] = "frsqrte.dFG",

      [37] = "fmov.sFG",
      [38] = "fmov.dFG",
      [41] = "movgr2fr.wFJ",
      [42] = "movgr2fr.dFJ",
      [43] = "movgr2frh.wFJ",
      [45] = "movfr2gr.sDG",
      [46] = "movfr2gr.dDG",
      [47] = "movfrh2gr.sDG",
      [48] = "movgr2fcsrSJ",
      [50] = "movfcsr2grDR",
      [52] = { shift = 3, mask = 0x3, [0] = "movfr2cfEG", },
      [53] = { shift = 8, mask = 0x3, [0] = "movcf2frFA", },
      [54] = { shift = 3, mask = 0x3, [0] = "movgr2cfEJ", },
      [55] = { shift = 8, mask = 0x3, [0] = "movcf2grDA", },
    },
    [6] = {
      shift = 10, mask = 0xff,
      [70] = "fcvt.s.dFG",
      [73] = "fcvt.d.sFG",
      [129] = "ftintrm.w.sFG",
      [130] = "ftintrm.w.dFG",
      [137] = "ftintrm.l.sFG",
      [138] = "ftintrm.l.dFG",
      [145] = "ftintrp.w.sFG",
      [146] = "ftintrp.w.dFG",
      [153] = "ftintrp.l.sFG",
      [154] = "ftintrp.l.dFG",
      [161] = "ftintrz.w.sFG",
      [162] = "ftintrz.w.dFG",
      [169] = "ftintrz.l.sFG",
      [170] = "ftintrz.l.dFG",
      [177] = "ftintrne.w.sFG",
      [178] = "ftintrne.w.dFG",
      [185] = "ftintrne.l.sFG",
      [186] = "ftintrne.l.dFG",
      [193] = "ftint.w.sFG",
      [194] = "ftint.w.dFG",
      [201] = "ftint.l.sFG",
      [202] = "ftint.l.dFG",
    },
    [7] = {
      shift = 10, mask = 0xff,
      [68] = "ffint.s.wFG",
      [70] = "ffint.s.lFG",
      [72] = "ffint.d.wFG",
      [74] = "ffint.d.lFG",
      [145] = "frint.sFG",
      [148] = "frint.dFG",
    },
  },
}

local map_zero_31_26 = { -- [31:26] = 0
  shift = 25, mask = 0x1,
  [0] = map_zero_31_25,
  [1] = {
    shift = 22, mask = 0x7,
    [0] = "sltiDJX",
    [1] = "sltuiDJX",
    [2] = "addi.wDJX",
    [3] = "addi.dDJX",
    [4] = "lu52i.dDJX",
    [5] = "andiDJT",
    [6] = "oriDJT",
    [7] = "xoriDJT",
  },
}

local map_zero_31_28 = { -- [31:28] = 0
  shift = 26, mask = 0x3,
  [0] = map_zero_31_26,
  [2] = {
    shift = 20, mask = 0x3f,
    [1] = "fmadd.sFGHi",
    [2] = "fmadd.dFGHi",
    [5] = "fmsub.sFGHi",
    [6] = "fmsub.dFGHi",
    [9] = "fnmadd.sFGHi",
    [10] = "fnmadd.dFGHi",
    [13] = "fnmsub.sFGHi",
    [14] = "fnmsub.dFGHi",
  },
  [3] = {
    shift = 20, mask = 0x7,
    [1] = {
      shift = 15, mask = 0x1f,
      [0] = "fcmp.caf.EGH",
      [1] = "fcmp.saf.EGH",
      [2] = "fcmp.clt.EGH",
      [3] = "fcmp.slt.EGH",
      [4] = "fcmp.ceq.EGH",
      [5] = "fcmp.seq.EGH",
      [6] = "fcmp.cle.EGH",
      [7] = "fcmp.sle.EGH",
      [8] = "fcmp.cun.EGH",
      [9] = "fcmp.sun.EGH",
      [10] = "fcmp.cult.EGH",
      [11] = "fcmp.sult.EGH",
      [12] = "fcmp.cueq.EGH",
      [13] = "fcmp.sueq.EGH",
      [14] = "fcmp.cule.EGH",
      [15] = "fcmp.sule.EGH",
      [16] = "fcmp.cne.EGH",
      [17] = "fcmp.sne.EGH",
      [20] = "fcmp.cor.EGH",
      [21] = "fcmp.sor.EGH",
      [24] = "fcmp.cune.EGH",
      [25] = "fcmp.sune.EGH",
    },
    [2] = {
      shift = 15, mask = 0x1f,
      [0] = "fcmp.caf.EGH",
      [1] = "fcmp.saf.EGH",
      [2] = "fcmp.clt.EGH",
      [3] = "fcmp.slt.EGH",
      [4] = "fcmp.ceq.EGH",
      [5] = "fcmp.seq.EGH",
      [6] = "fcmp.cle.EGH",
      [7] = "fcmp.sle.EGH",
      [8] = "fcmp.cun.EGH",
      [9] = "fcmp.sun.EGH",
      [10] = "fcmp.cult.EGH",
      [11] = "fcmp.sult.EGH",
      [12] = "fcmp.cueq.EGH",
      [13] = "fcmp.sueq.EGH",
      [14] = "fcmp.cule.EGH",
      [15] = "fcmp.sule.EGH",
      [16] = "fcmp.cne.EGH",
      [17] = "fcmp.sne.EGH",
      [20] = "fcmp.cor.EGH",
      [21] = "fcmp.sor.EGH",
      [24] = "fcmp.cune.EGH",
      [25] = "fcmp.sune.EGH",
    },
    [16] = {
      shift = 18, mask = 0x3,
      [0] = "fselFGHI",
    },
  },
}

local map_zero_31_29 = { -- [31:29] = 0
  shift = 28, mask = 0x1,
  [0] = map_zero_31_28,
  [1] = {
    shift = 26, mask = 0x3,
    [0] = "addu16i.dDJY",
    [1] = {
      shift = 25, mask = 0x1,
      [0] = "lu12i.wDZ",
      [1] = "lu32i.dDZ",
    },
    [2] = {
      shift = 25, mask = 0x1,
      [0] = "pcaddiDZ",
      [1] = "pcalau12iDZ",
    },
    [3] = {
      shift = 25, mask = 0x1,
      [0] = "pcaddu12iDZ",
      [1] = "pcaddu18iDZ",
    },
  },
}

local map_zero_31_31 = { -- [31:31] = 0
  shift = 29, mask = 0x3,
  [0] = map_zero_31_29,
  [1] = {
    shift = 27, mask = 0x3,
    [0] = {
      shift = 24, mask = 0x7,
      [0] = "ll.wDJW",
      [1] = "sc.wDJW",
      [2] = "ll.dDJW",
      [3] = "sc.dDJW",
      [4] = "ldptr.wDJW",
      [5] = "stptr.wDJW",
      [6] = "ldptr.dDJW",
      [7] = "stptr.dDJW",
    },
    [1] = {
      shift = 22, mask = 0x1f,
      [0] = "ld.bDJX",
      [1] = "ld.hDJX",
      [2] = "ld.wDJX",
      [3] = "ld.dDJX",
      [4] = "st.bDJX",
      [5] = "st.hDJX",
      [6] = "st.wDJX",
      [7] = "st.dDJX",
      [8] = "ld.buDJX",
      [9] = "ld.huDJX",
      [10] = "ld.wuDJX",
      [12] = "fld.sFJX",
      [13] = "fst.sFJX",
      [14] = "fld.dFJX",
      [15] = "fst.dFJX",
    },
    [3] = {
      shift = 21, mask = 0x3f,
      [0] = {
        shift = 15, mask = 0x3f,
        [0] = "ldx.bDJK",
        [8] = "ldx.hDJK",
        [16] = "ldx.wDJK",
        [24] = "ldx.dDJK",
        [32] = "stx.bDJK",
        [40] = "stx.hDJK",
        [48] = "stx.wDJK",
        [56] = "stx.dDJK",
      },
      [1] = {
        shift = 15, mask = 0x3f,
        [0] = "ldx.buDJK",
        [8] = "ldx.huDJK",
        [16] = "ldx.wuDJK",
        [32] = "fldx.sFJK",
        [40] = "fldx.dFJK",
        [48] = "fstx.sFJK",
        [56] = "fstx.dFJK",
      },
      [2] = {
        shift = 15, mask = 0x3f,
        [46] = "sc.wDJW",
      },
      [3] = {
        shift = 15, mask = 0x3f,
        [40] = "fldgt.sFJK",
        [41] = "fldgt.dFJK",
        [42] = "fldle.sFJK",
        [43] = "fldle.dFJK",
        [44] = "fstgt.sFJK",
        [45] = "fstgt.dFJK",
        [46] = "fstle.sFJK",
        [47] = "fstle.dFJK",
        [48] = "ldgt.bDJK",
        [49] = "ldgt.hDJK",
        [50] = "ldgt.wDJK",
        [51] = "ldgt.dDJK",
        [52] = "ldle.bDJK",
        [53] = "ldle.hDJK",
        [54] = "ldle.wDJK",
        [55] = "ldle.dDJK",
        [56] = "stgt.bDJK",
        [57] = "stgt.hDJK",
        [58] = "stgt.wDJK",
        [59] = "stgt.dDJK",
        [60] = "stle.bDJK",
        [61] = "stle.hDJK",
        [62] = "stle.wDJK",
        [63] = "stle.dDJK",
      },
    },
  },
  [2] = {
    shift = 26, mask = 0x7,
    [0] = "beqzJL",
    [1] = "bnezJL",
    [2] = { shift = 8, mask = 3, [0] = "bceqzAL", "bcnezAL", },
    [3] = "jirlDJO",
    [4] = "bP",
    [5] = "blP",
    [6] = "beqJDO",
    [7] = "bneJDO",
  },
  [3] = {
    shift = 26, mask = 0x7,
    [0] = "bltJDO",
    [1] = "bgeJDO",
    [2] = "bltuJDO",
    [3] = "bgeuJDO",
  },
}

local map_init = map_zero_31_31

------------------------------------------------------------------------------

local map_gpr = {
  [0] = "r0", "ra", "r2", "sp", "r4", "r5", "r6", "r7",
  "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
  "r16", "r17", "r18", "r19", "r20", "r21", "r22", "r23",
  "r24", "r25", "r26", "r27", "r28", "r29", "r30", "r31",
}

local map_fpr = {
  [0] = "f0", "f1", "f2", "f3", "f4", "f5", "f6", "f7",
  "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15",
  "f16", "f17", "f18", "f19", "f20", "f21", "f22", "f23",
  "f24", "f25", "f26", "f27", "f28", "f29", "f30", "f31",
}
------------------------------------------------------------------------------

-- Output a nicely formatted line with an opcode and operands.
local function putop(ctx, text, operands)
  local pos = ctx.pos
  local extra = ""
  if ctx.rel then
    local sym = ctx.symtab[ctx.rel]
    if sym then extra = "\t->"..sym end
  end
  if ctx.hexdump > 0 then
    ctx.out(format("%08x  %s  %-7s %s%s\n",
	    ctx.addr+pos, tohex(ctx.op), text, concat(operands, ", "), extra))
  else
    ctx.out(format("%08x  %-7s %s%s\n",
	    ctx.addr+pos, text, concat(operands, ", "), extra))
  end
  ctx.pos = pos + 4
end

-- Fallback for unknown opcodes.
local function unknown(ctx)
  return putop(ctx, ".long", { "0x"..tohex(ctx.op) })
end

local function get_le(ctx)
  local pos = ctx.pos
  local b0, b1, b2, b3 = byte(ctx.code, pos+1, pos+4)
  return bor(lshift(b3, 24), lshift(b2, 16), lshift(b1, 8), b0)
end

-- Decode a signed immediate value
local function decode_simm(ctx, op, shift, bits, hex_digits)
  local mask = lshift(1, bits) - 1
  local val = band(rshift(op, shift), mask)
  if band(val, lshift(1, bits-1)) ~= 0 then
    val = val - lshift(1, bits)
  end
  ctx.rel = val
  if hex_digits then
    local fmt = "%d(0x%0"..hex_digits.."x)"
    return format(fmt, val, band(val, mask))
  else
    return format("%d(0x%x)", val, band(val, mask))
  end
end

-- Similar for unsigned immediate (no sign extension)
local function decode_uimm(ctx, op, shift, bits, hex_digits)
  local mask = lshift(1, bits) - 1
  local val = band(rshift(op, shift), mask)
  ctx.rel = val
  if hex_digits then
    local fmt = "%d(0x%0"..hex_digits.."x)"
    return format(fmt, val, val)
  else
    return format("%d(0x%x)", val, val)
  end
end

-- Decode a PC-relative branch offset
local function decode_offs(ctx, offs, bits)
  local mask = lshift(1, bits) - 1
  if band(offs, lshift(1, bits-1)) ~= 0 then
    offs = offs - lshift(1, bits)
  end
  -- branch offsets are in units of 4 bytes (<< 2)
  local target = ctx.addr + ctx.pos + lshift(offs, 2)
  ctx.rel = target
  return format("0x%08x", target)
end

-- Disassemble a single instruction.
local function disass_ins(ctx)
  local op = ctx:get()
  local operands = {}
  ctx.op = op
  ctx.rel = nil

  local opat = ctx.map_pri[band(rshift(op, ctx.map_pri.shift), ctx.map_pri.mask)]
  while type(opat) ~= "string" do
    if not opat then return unknown(ctx) end
    opat = opat[band(rshift(op, opat.shift), opat.mask)]
  end

  local name, pat = match(opat, "^([a-z0-9.]*)(.*)")
  for p in gmatch(pat, ".") do
    local x = nil
    if p == "D" then -- rd
      x = map_gpr[band(op, 0x1f)]
    elseif p == "J" then -- rj
      x = map_gpr[band(rshift(op, 5), 0x1f)]
    elseif p == "K" then -- rk
      x = map_gpr[band(rshift(op, 10), 0x1f)]
    elseif p == "F" then -- fd
      x = map_fpr[band(op, 0x1f)]
    elseif p == "G" then -- fj
      x = map_fpr[band(rshift(op, 5), 0x1f)]
    elseif p == "H" then -- fk
      x = map_fpr[band(rshift(op, 10), 0x1f)]
    elseif p == "i" then  -- fa
      x = map_fpr[band(rshift(op, 15), 0x1f)]
    elseif p == "S" then  -- fcsr
      x = "fcsr"..band(op, 0x1f)
    elseif p == "R" then  -- fcsr
      x = "fcsr"..band(rshift(op, 5), 0x1f)
    elseif p == "E" then  -- cd
      x = "fcc"..band(op, 0x7)
    elseif p == "A" then  -- cj
      x = "fcc"..band(rshift(op, 5), 0x7)
    elseif p == "I" then  -- ca
      x = "fcc"..band(rshift(op, 15), 0x7)
    elseif p == "Q" then -- sa2
      x = decode_uimm(ctx, op, 15, 2, nil)
    elseif p == "B" then -- sa3
      x = decode_uimm(ctx, op, 15, 3, nil)
    elseif p == "M" then -- msbw
      x = decode_uimm(ctx, op, 16, 5, 2)
    elseif p == "N" then -- msbd
      x = decode_uimm(ctx, op, 16, 6, 2)
    elseif p == "U" then -- ui5
      x = decode_uimm(ctx, op, 10, 5, 2)
    elseif p == "V" then -- ui6
      x = decode_uimm(ctx, op, 10, 6, 2)
    elseif p == "T" then -- ui12
      x = decode_uimm(ctx, op, 10, 12, 3)
    elseif p == "W" then -- si14
      x = decode_simm(ctx, op, 10, 14, 4)
    elseif p == "X" then -- si12
      x = decode_simm(ctx, op, 10, 12, 3)
    elseif p == "Y" then -- si16
      x = decode_simm(ctx, op, 10, 16, 4)
    elseif p == "Z" then -- si20
      x = decode_simm(ctx, op, 5, 20, 5)
    elseif p == "C" then -- code
      x = band(op, 0x1f)
    elseif p == "O" then -- offs[15:0]
      if name == "jirl" then
        x = decode_simm(ctx, op, 10, 16, 4)
      else
        local offs = band(rshift(op, 10), 0xffff)
        x = decode_offs(ctx, offs, 16)
      end
    elseif p == "L" then -- offs[15:0] + offs[20:16]
      local offs = lshift(band(op, 0x1f), 16) + band(rshift(op, 10), 0xffff)
      x = decode_offs(ctx, offs, 21)
    elseif p == "P" then -- offs[15:0] + offs[25:16]
      local offs = lshift(band(op, 0x3ff), 16) + band(rshift(op, 10), 0xffff)
      x = decode_offs(ctx, offs, 26)
    else
      assert(false)
    end
    if x then operands[#operands+1] = x end
  end

  return putop(ctx, name, operands)
end

------------------------------------------------------------------------------

-- Disassemble a block of code.
local function disass_block(ctx, ofs, len)
  if not ofs then ofs = 0 end
  local stop = len and ofs+len or #ctx.code
  stop = stop - stop % 4
  ctx.pos = ofs - ofs % 4
  ctx.rel = nil
  while ctx.pos < stop do disass_ins(ctx) end
end

-- Extended API: create a disassembler context. Then call ctx:disass(ofs, len).
local function create(code, addr, out)
  local ctx = {}
  ctx.code = code
  ctx.addr = addr or 0
  ctx.out = out or io.write
  ctx.symtab = {}
  ctx.disass = disass_block
  ctx.hexdump = 8
  ctx.get = get_le
  ctx.map_pri = map_init
  return ctx
end

-- Simple API: disassemble code (a string) at address and output via out.
local function disass(code, addr, out)
  create(code, addr, out):disass()
end

-- Return register name for RID.
local function regname(r)
  if r < 32 then return map_gpr[r] end
  return map_fpr[r-32]
end

-- Public module functions.
return {
  create = create,
  disass = disass,
  regname = regname
}

