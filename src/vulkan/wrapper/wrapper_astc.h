/*
 * Minimal ASTC 4x4 LDR encoder for transcoding BCn textures.
 *
 * Two per-block configurations, both matching the block layout parsed by
 * Mesa's _mesa_unpack_astc_2d_ldr decoder (validated offline by round-trip):
 *
 *   RGB  (opaque, has_alpha==0): single plane, CEM 8 (LDR RGB direct),
 *      8-level (3-bit) weights, pure 8-bit endpoints. block mode 0x53.
 *
 *   RGBA (has_alpha==1): DUAL plane so alpha gets its own interpolation weight
 *      (independent of RGB). CEM 12 (LDR RGBA direct), 4-level (2-bit) weights
 *      per plane, colour-component-selector = alpha. The 4x4 dual-plane bit
 *      budget forces trit-encoded endpoints (range 47); the trit ISE tables and
 *      the endpoint unquantization table below were derived from Mesa's decoder.
 *      block mode 0x442.
 *
 * Mali samples ASTC natively, so BCn textures stay ~compressed in GPU memory
 * instead of being decoded to RGBA8 (4-8x larger).
 */
#ifndef WRAPPER_ASTC_H
#define WRAPPER_ASTC_H

#include <stdint.h>
#include <string.h>

/* trit ISE encode: index t0+3t1+9t2+27t3+81t4 -> 8-bit T field (5 values). */
static const uint8_t astc_trit5[243] = {
  0,1,2,4,5,6,8,9,10,16,17,18,20,21,22,24,
  25,26,3,7,11,19,23,27,12,13,14,32,33,34,36,37,
  38,40,41,42,48,49,50,52,53,54,56,57,58,35,39,43,
  51,55,59,44,45,46,64,65,66,68,69,70,72,73,74,80,
  81,82,84,85,86,88,89,90,67,71,75,83,87,91,76,77,
  78,128,129,130,132,133,134,136,137,138,144,145,146,148,149,150,
  152,153,154,131,135,139,147,151,155,140,141,142,160,161,162,164,
  165,166,168,169,170,176,177,178,180,181,182,184,185,186,163,167,
  171,179,183,187,172,173,174,192,193,194,196,197,198,200,201,202,
  208,209,210,212,213,214,216,217,218,195,199,203,211,215,219,204,
  205,206,96,97,98,100,101,102,104,105,106,112,113,114,116,117,
  118,120,121,122,99,103,107,115,119,123,108,109,110,224,225,226,
  228,229,230,232,233,234,240,241,242,244,245,246,248,249,250,227,
  231,235,243,247,251,236,237,238,28,29,30,60,61,62,92,93,
  94,156,157,158,188,189,190,220,221,222,31,63,95,159,191,223,
  124,125,126,
};
/* trit ISE encode: index t0+3t1+9t2 -> value 0..31 (T5=T6=T7=0), partial (3 values). */
static const uint8_t astc_trit3[27] = {
  0,1,2,4,5,6,8,9,10,16,17,18,20,21,22,24,
  25,26,3,7,11,19,23,27,12,13,14,
};
/* Endpoint unquantization for range 47 (4-bit + trit): quant level -> 0..255. */
static const uint8_t astc_ce_unq[48] = {
  0,255,16,239,32,223,48,207,65,190,81,174,97,158,113,142,
  5,250,21,234,38,217,54,201,70,185,86,169,103,152,119,136,
  11,244,27,228,43,212,59,196,76,179,92,163,108,147,124,131,
};

static inline void
astc_set_bits(uint8_t *blk, int pos, int count, uint32_t value)
{
   for (int i = 0; i < count; i++) {
      if (value & (1u << i))
         blk[(pos + i) >> 3] |= 1u << ((pos + i) & 7);
   }
}

static inline uint32_t
astc_reverse_bits(uint32_t v, int count)
{
   uint32_t out = 0;
   for (int i = 0; i < count; i++)
      out |= ((v >> i) & 1u) << (count - 1 - i);
   return out;
}

/* Farthest-apart pair of texels in RGB space -> endpoint indices. BCn source
 * data lies on a line per block, so this recovers that line. */
static inline void
astc_rgb_endpoints(const uint8_t texels[64], int *ai, int *bi)
{
   long best = -1;
   *ai = 0; *bi = 0;
   for (int i = 0; i < 16; i++) {
      for (int j = i + 1; j < 16; j++) {
         long d2 = 0;
         for (int c = 0; c < 3; c++) {
            long dc = (long)texels[i * 4 + c] - texels[j * 4 + c];
            d2 += dc * dc;
         }
         if (d2 > best) { best = d2; *ai = i; *bi = j; }
      }
   }
}

/* RGB single-plane block: CEM 8, 3-bit weights, 8-bit endpoints. */
static inline void
astc_encode_rgb_4x4(const uint8_t texels[64], uint8_t out[16])
{
   memset(out, 0, 16);

   int ai, bi;
   astc_rgb_endpoints(texels, &ai, &bi);
   const uint8_t *pa = &texels[ai * 4];
   const uint8_t *pb = &texels[bi * 4];
   int sa = pa[0] + pa[1] + pa[2];
   int sb = pb[0] + pb[1] + pb[2];
   const uint8_t *lo = (sb >= sa) ? pa : pb;   /* smaller sum -> e0 (no blue contract) */
   const uint8_t *hi = (sb >= sa) ? pb : pa;
   int e0[3] = { lo[0], lo[1], lo[2] };
   int e1[3] = { hi[0], hi[1], hi[2] };

   astc_set_bits(out, 0, 11, 0x53);
   astc_set_bits(out, 13, 4, 8);
   astc_set_bits(out, 17 + 0,  8, e0[0]);
   astc_set_bits(out, 17 + 8,  8, e1[0]);
   astc_set_bits(out, 17 + 16, 8, e0[1]);
   astc_set_bits(out, 17 + 24, 8, e1[1]);
   astc_set_bits(out, 17 + 32, 8, e0[2]);
   astc_set_bits(out, 17 + 40, 8, e1[2]);

   int dir[3];
   long dlen2 = 0;
   for (int c = 0; c < 3; c++) { dir[c] = e1[c] - e0[c]; dlen2 += (long)dir[c] * dir[c]; }

   for (int t = 0; t < 16; t++) {
      int q;
      if (dlen2 == 0) {
         q = 0;
      } else {
         long dot = 0;
         for (int c = 0; c < 3; c++)
            dot += (long)(texels[t * 4 + c] - e0[c]) * dir[c];
         if (dot <= 0) q = 0;
         else if (dot >= dlen2) q = 7;
         else q = (int)((dot * 7 + dlen2 / 2) / dlen2);
      }
      astc_set_bits(out, 128 - (t + 1) * 3, 3, astc_reverse_bits((uint32_t)q, 3));
   }
}

/* Trit bit positions within a 4-bit-mantissa trit group (ce_bits==4). */
static const int astc_trit_Tpos[8] = { 4, 5, 10, 11, 16, 21, 22, 27 };
static const int astc_trit_Mpos[5] = { 0, 6, 12, 17, 23 };

/* Write 8 endpoint quant levels (0..47) as two trit groups from bit 17. */
static inline void
astc_write_trit_endpoints(uint8_t *blk, const int q[8])
{
   int base = 17;
   int t = astc_trit5[(q[0] >> 4) + 3 * (q[1] >> 4) + 9 * (q[2] >> 4) +
                      27 * (q[3] >> 4) + 81 * (q[4] >> 4)];
   for (int j = 0; j < 5; j++)
      astc_set_bits(blk, base + astc_trit_Mpos[j], 4, q[j] & 15);
   for (int j = 0; j < 8; j++)
      if ((t >> j) & 1) astc_set_bits(blk, base + astc_trit_Tpos[j], 1, 1);

   base = 45;
   int t3 = astc_trit3[(q[5] >> 4) + 3 * (q[6] >> 4) + 9 * (q[7] >> 4)];
   for (int j = 0; j < 3; j++)
      astc_set_bits(blk, base + astc_trit_Mpos[j], 4, q[5 + j] & 15);
   for (int j = 0; j < 5; j++)   /* only T0..T4 fit before the CCS at bit 62 */
      if ((t3 >> j) & 1) astc_set_bits(blk, base + astc_trit_Tpos[j], 1, 1);
}

static inline int
astc_quantize_ce(int v)
{
   int best = 0, bd = 1 << 30;
   for (int L = 0; L < 48; L++) {
      int d = astc_ce_unq[L] - v;
      if (d < 0) d = -d;
      if (d < bd) { bd = d; best = L; }
   }
   return best;
}

/* RGBA dual-plane block: CEM 12, 2-bit weights per plane, alpha on plane 1. */
static inline void
astc_encode_rgba_4x4(const uint8_t texels[64], uint8_t out[16])
{
   memset(out, 0, 16);
   astc_set_bits(out, 0, 11, 0x442);
   astc_set_bits(out, 13, 4, 12);

   int ai, bi;
   astc_rgb_endpoints(texels, &ai, &bi);
   const uint8_t *pa = &texels[ai * 4];
   const uint8_t *pb = &texels[bi * 4];
   int sa = pa[0] + pa[1] + pa[2];
   int sb = pb[0] + pb[1] + pb[2];
   const uint8_t *lo = (sb >= sa) ? pa : pb;
   const uint8_t *hi = (sb >= sa) ? pb : pa;

   int amin = 255, amax = 0;
   for (int i = 0; i < 16; i++) {
      int a = texels[i * 4 + 3];
      if (a < amin) amin = a;
      if (a > amax) amax = a;
   }
   int e0[4] = { lo[0], lo[1], lo[2], amin };
   int e1[4] = { hi[0], hi[1], hi[2], amax };

   int q[8] = {
      astc_quantize_ce(e0[0]), astc_quantize_ce(e1[0]),
      astc_quantize_ce(e0[1]), astc_quantize_ce(e1[1]),
      astc_quantize_ce(e0[2]), astc_quantize_ce(e1[2]),
      astc_quantize_ce(e0[3]), astc_quantize_ce(e1[3]),
   };

   /* Guarantee s1>=s0 on the unquantized RGB sums (quantization can flip a
    * near-tie); otherwise the decoder blue-contracts and corrupts the block. */
   int s0 = astc_ce_unq[q[0]] + astc_ce_unq[q[2]] + astc_ce_unq[q[4]];
   int s1 = astc_ce_unq[q[1]] + astc_ce_unq[q[3]] + astc_ce_unq[q[5]];
   int swap = s1 < s0;
   if (swap)
      for (int k = 0; k < 8; k += 2) { int tmp = q[k]; q[k] = q[k + 1]; q[k + 1] = tmp; }

   astc_write_trit_endpoints(out, q);
   astc_set_bits(out, 62, 2, 3);   /* CCS = alpha component */

   int dir[3];
   long dlen2 = 0;
   for (int c = 0; c < 3; c++) { dir[c] = e1[c] - e0[c]; dlen2 += (long)dir[c] * dir[c]; }
   int arange = amax - amin;

   for (int px = 0; px < 16; px++) {
      int q0;
      if (dlen2 == 0) {
         q0 = 0;
      } else {
         long dot = 0;
         for (int c = 0; c < 3; c++)
            dot += (long)(texels[px * 4 + c] - e0[c]) * dir[c];
         if (dot <= 0) q0 = 0;
         else if (dot >= dlen2) q0 = 3;
         else q0 = (int)((dot * 3 + dlen2 / 2) / dlen2);
      }
      int q1;
      if (arange == 0) {
         q1 = 0;
      } else {
         int a = texels[px * 4 + 3] - amin;
         q1 = (a * 3 + arange / 2) / arange;
         if (q1 < 0) q1 = 0;
         if (q1 > 3) q1 = 3;
      }
      if (swap) { q0 = 3 - q0; q1 = 3 - q1; }
      astc_set_bits(out, 128 - (2 * px + 1) * 2, 2, astc_reverse_bits((uint32_t)q0, 2));
      astc_set_bits(out, 128 - (2 * px + 2) * 2, 2, astc_reverse_bits((uint32_t)q1, 2));
   }
}

/* Encode a 4x4 RGBA8 block (16 texels, row-major) into a 16-byte ASTC block. */
static inline void
astc_encode_block_4x4(const uint8_t texels[64], int has_alpha, uint8_t out[16])
{
   if (has_alpha)
      astc_encode_rgba_4x4(texels, out);
   else
      astc_encode_rgb_4x4(texels, out);
}

#endif /* WRAPPER_ASTC_H */
