/*
 * Minimal ASTC 4x4 LDR encoder.
 *
 * Fixed configuration per block: single partition, single plane, low
 * precision, 4x4 weight grid. Two variants:
 *   - RGB  (no alpha): CEM 8  (LDR RGB direct),  8-level (3-bit) weights
 *   - RGBA (alpha)   : CEM 12 (LDR RGBA direct), 4-level (2-bit) weights
 * Endpoints are stored at the pure 8-bit range (256 levels, identity
 * unquantization) so there is no endpoint quantization error; the only loss
 * is the bounding-box endpoint fit plus the weight quantization. This matches
 * the block layout parsed by Mesa's _mesa_unpack_astc_2d_ldr decoder.
 *
 * Used to keep BCn game textures compressed in GPU memory on Mali (which
 * samples ASTC natively) instead of decoding them to RGBA8 (4-8x larger).
 */
#ifndef WRAPPER_ASTC_H
#define WRAPPER_ASTC_H

#include <stdint.h>
#include <string.h>

/* RGB variant: block mode 0x53 (wt 4x4, single plane, low prec, range 0x7 -> 3-bit) */
#define ASTC_BLOCKMODE_RGB  0x53
/* RGBA variant: block mode 0x42 (wt 4x4, single plane, low prec, range 0x4 -> 2-bit) */
#define ASTC_BLOCKMODE_RGBA 0x42

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

/* Encode a single 4x4 RGBA8 block (16 texels, row-major, 4 bytes/texel) into a
 * 16-byte ASTC block. If has_alpha is zero, alpha is ignored (RGB variant). */
static inline void
astc_encode_block_4x4(const uint8_t texels[64], int has_alpha, uint8_t out[16])
{
   memset(out, 0, 16);

   /* Principal-axis endpoints: the farthest-apart pair of texels in RGB space.
    * BCn source data already lies on a line per 4x4 block, so this recovers
    * that line (unlike a bounding box, which fails on anti-correlated blocks).
    * Alpha rides along the same weight from the two chosen texels' alpha. */
   int ai = 0, bi = 0;
   long best = -1;
   for (int i = 0; i < 16; i++) {
      for (int j = i + 1; j < 16; j++) {
         long d2 = 0;
         for (int c = 0; c < 3; c++) {
            long dc = (long)texels[i * 4 + c] - texels[j * 4 + c];
            d2 += dc * dc;
         }
         if (d2 > best) { best = d2; ai = i; bi = j; }
      }
   }

   const uint8_t *pa = &texels[ai * 4];
   const uint8_t *pb = &texels[bi * 4];
   /* e0 = smaller RGB sum, e1 = larger, so the decoder takes the direct
    * (non blue-contract) endpoint assignment. */
   int sa = pa[0] + pa[1] + pa[2];
   int sb = pb[0] + pb[1] + pb[2];
   const uint8_t *lo = (sb >= sa) ? pa : pb;
   const uint8_t *hi = (sb >= sa) ? pb : pa;

   int e0[4] = { lo[0], lo[1], lo[2], has_alpha ? lo[3] : 255 };
   int e1[4] = { hi[0], hi[1], hi[2], has_alpha ? hi[3] : 255 };

   int wt_bits = has_alpha ? 2 : 3;
   int levels = has_alpha ? 4 : 8; /* weight levels (wt_max + 1) */

   /* Direction vector and squared length for projection (RGB axis). */
   int dir[3];
   long dlen2 = 0;
   for (int c = 0; c < 3; c++) {
      dir[c] = e1[c] - e0[c];
      dlen2 += (long)dir[c] * dir[c];
   }

   /* Header. */
   int block_mode = has_alpha ? ASTC_BLOCKMODE_RGBA : ASTC_BLOCKMODE_RGB;
   astc_set_bits(out, 0, 11, block_mode);
   /* bits [12:11] = num partitions - 1 = 0 */
   astc_set_bits(out, 13, 4, has_alpha ? 12 : 8); /* CEM */

   /* Color endpoints at bit 17, 8 bits each, interleaved e0/e1 per channel. */
   int off = 17;
   astc_set_bits(out, off + 0,  8, e0[0]); /* R0 */
   astc_set_bits(out, off + 8,  8, e1[0]); /* R1 */
   astc_set_bits(out, off + 16, 8, e0[1]); /* G0 */
   astc_set_bits(out, off + 24, 8, e1[1]); /* G1 */
   astc_set_bits(out, off + 32, 8, e0[2]); /* B0 */
   astc_set_bits(out, off + 40, 8, e1[2]); /* B1 */
   if (has_alpha) {
      astc_set_bits(out, off + 48, 8, e0[3]); /* A0 */
      astc_set_bits(out, off + 56, 8, e1[3]); /* A1 */
   }

   /* Per-texel weights, stored bit-reversed from the top of the block. */
   for (int t = 0; t < 16; t++) {
      int q;
      if (dlen2 == 0) {
         q = 0;
      } else {
         long dot = 0;
         for (int c = 0; c < 3; c++)
            dot += (long)(texels[t * 4 + c] - e0[c]) * dir[c];
         /* w in [0,1] -> quantize to [0, levels-1] */
         if (dot <= 0)
            q = 0;
         else if (dot >= dlen2)
            q = levels - 1;
         else
            q = (int)((dot * (levels - 1) + dlen2 / 2) / dlen2);
      }

      uint32_t rev = astc_reverse_bits((uint32_t)q, wt_bits);
      int pos = 128 - (t + 1) * wt_bits;
      astc_set_bits(out, pos, wt_bits, rev);
   }
}

#endif /* WRAPPER_ASTC_H */
