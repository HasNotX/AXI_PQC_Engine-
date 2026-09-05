def bit_reverse(val, width):
    return int('{:0{w}b}'.format(val, w=width)[::-1], 2)

def generate_twiddles(q, zeta, num_twiddles, bit_width):
    twiddles = []
    for i in range(num_twiddles):
        br_i = bit_reverse(i, bit_width)
        # Standard domain: just (zeta ^ br_i) mod q
        val = pow(zeta, br_i, q)
        twiddles.append(val)
    return twiddles

def pack_to_128bit_hex(twiddles):
    lines = []
    # Pack 4 constants per 128-bit row
    for i in range(0, len(twiddles), 4):
        z0 = twiddles[i]
        z1 = twiddles[i+1]
        z2 = twiddles[i+2]
        z3 = twiddles[i+3]
        # Format as 32-bit hex strings, concatenated (z3, z2, z1, z0)
        hex_row = f"{z3:08x}{z2:08x}{z1:08x}{z0:08x}"
        lines.append(hex_row)
    return lines

# ==========================================
# 1. Kyber (ML-KEM) Constants
# ==========================================
KYBER_Q = 3329
KYBER_ZETA = 17
kyber_twiddles = generate_twiddles(KYBER_Q, KYBER_ZETA, 128, 7)
kyber_hex = pack_to_128bit_hex(kyber_twiddles)

# ==========================================
# 2. Dilithium (ML-DSA) Constants
# ==========================================
DIL_Q = 8380417
DIL_ZETA = 1753
dil_twiddles = generate_twiddles(DIL_Q, DIL_ZETA, 256, 8)
dil_hex = pack_to_128bit_hex(dil_twiddles)

# ==========================================
# 3. Write to .mem file for Vivado
# ==========================================
with open("twiddles.mem", "w") as f:
    f.write("// ==========================================\n")
    f.write("// KYBER (ML-KEM) - 32 Rows (Indices 0-31)\n")
    f.write("// ==========================================\n")
    for line in kyber_hex:
        f.write(line + "\n")
        
    f.write("\n// ==========================================\n")
    f.write("// DILITHIUM (ML-DSA) - 64 Rows (Indices 32-95)\n")
    f.write("// ==========================================\n")
    for line in dil_hex:
        f.write(line + "\n")

print("Generated twiddles.mem successfully!")


# ==========================================
# 4. Generate Comprehensive Hardware Test Vectors
# ==========================================
# Format: algo_mode math_mode ntt_inverse stage batch exp_z0 exp_z1 exp_z2 exp_z3

vectors = []

def get_expected(algo, is_intt, is_base_mul, stage, batch):
    twiddles = dil_twiddles if algo == 1 else kyber_twiddles
    max_stage = 7 if algo == 1 else 6
    
    # Exact stage boundaries
    stage_start_fwd = 1 << stage
    stage_start_inv = (1 << (stage + 1)) - 1
    
    shift_map = {0:5, 1:4, 2:3, 3:2, 4:1}
    batch_shift = shift_map.get(stage, 0)
    group_idx = batch >> batch_shift
    
    if is_base_mul:
        base_idx = (1 << max_stage) + (batch * 4)
        z0, z1, z2, z3 = twiddles[base_idx], twiddles[base_idx+1], twiddles[base_idx+2], twiddles[base_idx+3]
        
    elif stage == 7: # Full Mode
        if is_intt:
            base_idx = stage_start_inv - (batch * 4)
            z0, z1, z2, z3 = twiddles[base_idx], twiddles[base_idx-1], twiddles[base_idx-2], twiddles[base_idx-3]
        else:
            base_idx = stage_start_fwd + (batch * 4)
            z0, z1, z2, z3 = twiddles[base_idx], twiddles[base_idx+1], twiddles[base_idx+2], twiddles[base_idx+3]
            
    elif stage == 6: # Pair Mode
        if is_intt:
            base_idx = stage_start_inv - (batch * 2)
            z0 = z1 = twiddles[base_idx]
            z2 = z3 = twiddles[base_idx-1]
        else:
            base_idx = stage_start_fwd + (batch * 2)
            z0 = z1 = twiddles[base_idx]
            z2 = z3 = twiddles[base_idx+1]
            
    else: # Broadcast Mode (Stages 0-5)
        base_idx = (stage_start_inv - group_idx) if is_intt else (stage_start_fwd + group_idx)
        z0 = z1 = z2 = z3 = twiddles[base_idx]
        
    return z0, z1, z2, z3
    
def add_vector(algo, math_mode, inv, stage, batch):
    is_intt = (math_mode in [2, 3]) or inv
    is_base_mul = (math_mode in [4, 5])
    z0, z1, z2, z3 = get_expected(algo, is_intt, is_base_mul, stage, batch)
    vectors.append(f"{algo} {math_mode} {inv} {stage} {batch} {z0:08x} {z1:08x} {z2:08x} {z3:08x}")

# Generate all permutations for Kyber (algo=0, batches=32 for NTT)
for stage in range(7):
    for batch in range(32):
        add_vector(0, 0, 0, stage, batch) # FWD_NTT_KYB
        add_vector(0, 2, 1, stage, batch) # INV_NTT_KYB
        
for batch in range(16):                   # Kyber Base Mul only has 16 index steps (64 to 127)
    add_vector(0, 4, 0, 0, batch)         # B_MUL_KYB

# Generate all permutations for Dilithium (algo=1, batches=32 for NTT)
for stage in range(8):
    for batch in range(32):               # FIXED: N=256 means exactly 32 batches per stage!
        add_vector(1, 1, 0, stage, batch) # FWD_NTT_DIL
        add_vector(1, 3, 1, stage, batch) # INV_NTT_DIL
        
for batch in range(32):                   # Dilithium Base Mul has 32 index steps (128 to 255)
    add_vector(1, 5, 0, 0, batch)         # B_MUL_DIL

# Save the Golden Model
with open("tag_test_vectors.txt", "w") as f:
    f.write("\n".join(vectors) + "\n")

print("Generated tag_test_vectors.txt successfully!")