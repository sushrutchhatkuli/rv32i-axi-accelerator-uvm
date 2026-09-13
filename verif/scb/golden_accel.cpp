// =============================================================================
// File: golden_accel.cpp
// Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
// Description: Pure C++ Golden Reference Mathematical Predictor for the
//              Custom Matrix Accelerator.
//              Implements bit-exact signed Q8.8 fixed-point matrix multiplication
//              with saturation clamping:
//                - Max Positive: +127.996 (0x7FFF / 32767)
//                - Min Negative: -128.0   (0x8000 / -32768)
//              Exported to SystemVerilog via the standard IEEE DPI-C interface.
// =============================================================================

#include <stdint.h>
#include <stdio.h>

extern "C" {

/**
 * @brief Computes Matrix C = Matrix A * Matrix B in Q8.8 signed fixed-point precision.
 * 
 * @param mat_a Pointer to flat array of Matrix A elements (dim x dim, int16_t Q8.8)
 * @param mat_b Pointer to flat array of Matrix B elements (dim x dim, int16_t Q8.8)
 * @param mat_c Pointer to destination array for Matrix C (dim x dim, int16_t Q8.8)
 * @param dim   Matrix dimension N (e.g., 2 for 2x2, 4 for 4x4)
 */
void golden_matrix_multiply_q8_8(
    const int16_t* mat_a,
    const int16_t* mat_b,
    int16_t*       mat_c,
    int            dim
) {
    if (!mat_a || !mat_b || !mat_c || dim <= 0) {
        return;
    }

    for (int i = 0; i < dim; i++) {
        for (int j = 0; j < dim; j++) {
            int32_t accumulator = 0;

            for (int k = 0; k < dim; k++) {
                int16_t a_val = mat_a[i * dim + k];
                int16_t b_val = mat_b[k * dim + j];

                // 16-bit signed x 16-bit signed produces 32-bit product (Q16.16)
                int32_t product = (int32_t)a_val * (int32_t)b_val;

                // Arithmetic shift right by 8 bits aligns Q16.16 back to Q8.8 format
                int32_t product_shifted = product >> 8;

                accumulator += product_shifted;
            }

            // Saturation clamping to 16-bit signed Q8.8 range [-32768, 32767]
            if (accumulator > 32767) {
                mat_c[i * dim + j] = 32767;          // Clamp to +127.996 (0x7FFF)
            } else if (accumulator < -32768) {
                mat_c[i * dim + j] = -32768;         // Clamp to -128.0   (0x8000)
            } else {
                mat_c[i * dim + j] = (int16_t)accumulator;
            }
        }
    }
}

} // extern "C"
