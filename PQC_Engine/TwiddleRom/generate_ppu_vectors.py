import random

# ==========================================
# 1. Twiddle Generation (Exact same as TAG)
# ==========================================
def bit_reverse(val, width):
    return int('{:0{w}b}'.format(val, w=width)[::-1], 2)

def generate_twiddles(q, zeta, num_twiddles, bit_width):
    return [pow(zeta, bit_reverse(i, bit_width), q) for i in range(num_twiddles)]

KYBER_Q = 3329
KYBER_ZETA = 17
kyber_twiddles = generate_twiddles(KYBER_Q, KYBER_ZETA, 128, 7)

DIL_Q = 8380417
DIL_ZETA = 1753
dil_twiddles = generate_twiddles(DIL_Q, DIL_ZETA, 256, 8)

def get_zeta0(algo, is_intt, stage, batch):
    twiddles = dil_twiddles if algo == 1 else kyber_twiddles
    stage_start_fwd = 1 << stage
    stage_start_inv = (1 << (stage + 1)) - 1
    
    if stage == 7:
        base_idx = (stage_start_inv - (batch * 4)) if is_intt else (stage_start_fwd + (batch * 4))
        return twiddles[base_idx]
    elif stage == 6:
        base_idx = (stage_start_inv - (batch * 2)) if is_intt else (stage_start_fwd + (batch * 2))
        return twiddles[base_idx]
    else:
        shift_map = {0:5, 1:4, 2:3, 3:2, 4:1}
        batch_shift = shift_map.get(stage, 0)
        group_idx = batch >> batch_shift
        base_idx = (stage_start_inv - group_idx) if is_intt else (stage_start_fwd + group_idx)
        return twiddles[base_idx]

# ==========================================
# 2. Butterfly Math Simulation
# ==========================================
vectors = []

def generate_sequence(algo, is_intt, num_stages):
    q = DIL_Q if algo == 1 else KYBER_Q
    
    # FIX: Hardware runs FWD top-down (e.g. 6 to 0) and INV bottom-up (0 to 6)
    stage_list = range(num_stages) if is_intt else range(num_stages-1, -1, -1)
    
    for stage in stage_list:
        for batch in range(32):
            a = random.randint(0, q - 1)
            b = random.randint(0, q - 1)
            zeta = get_zeta0(algo, is_intt, stage, batch)
            
            if not is_intt:
                bz = (b * zeta) % q
                r0 = (a + bz) % q
                r1 = (a - bz) % q
                if r1 < 0: r1 += q 
            else:
                r0 = (a + b) % q
                r1 = ((a - b) * zeta) % q
                if r1 < 0: r1 += q
            
            vectors.append(f"{a:08x} {b:08x} {r0:08x} {r1:08x}")
            
# Generate Kyber FWD (224 lines) & INV (224 lines)
generate_sequence(algo=0, is_intt=False, num_stages=7)
generate_sequence(algo=0, is_intt=True,  num_stages=7)

# Generate Dilithium FWD (256 lines) & INV (256 lines)
generate_sequence(algo=1, is_intt=False, num_stages=8)
generate_sequence(algo=1, is_intt=True,  num_stages=8)

with open("math_vectors.txt", "w") as f:
    f.write("\n".join(vectors) + "\n")

print(f"Generated {len(vectors)} mathematical test vectors to math_vectors.txt")