import sys
import re
import argparse

Q = 3329
ZETA_BASE = 17

def bit_reverse(val, width):
    return int('{:0{width}b}'.format(val, width=width)[::-1], 2)

twiddles = [pow(ZETA_BASE, bit_reverse(i, 7), Q) for i in range(128)]

Q_DIL = 8380417
ZETA_BASE_DIL = 1753
twiddles_dil = [pow(ZETA_BASE_DIL, bit_reverse(i, 8), Q_DIL) for i in range(256)]

def parity(val):
    p = 0
    while val: 
        p ^= (val & 1)
        val >>= 1
    return p

def new_mangling(addr):
    bank_1_0 = addr & 0x3
    bank_2 = parity((addr >> 2) & 0x3F)
    bank = (bank_2 << 2) | bank_1_0
    offset = (addr >> 3) & 0x1F
    return bank, offset

def concat_mangling(addr):
    bank = addr & 0x7
    offset = (addr >> 3) & 0x1F
    return bank, offset

def parse_logs():
    reads = {0: {}, 1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 7: {}, 8: {}, 9: {}, 10: {}, 11: {}}
    writes = {0: {}, 1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 7: {}, 8: {}, 9: {}, 10: {}, 11: {}}
    writes_r1 = {6: {}, 7: {}}
    try:
        with open("sim_transcript.log", "r") as f:
            for line in f:
                m_rd = re.search(r"\[(\d+)\] AGU_FETCH:\s+stage=(\d+)\s+rd_batch=(\d+)\s+lane=(\d+)\s+fetched_a=([xXzZ\d]+)\s+fetched_b=([xXzZ\d]+)", line)
                if m_rd:
                    mode, stg, btch, ln = map(int, m_rd.groups()[:4])
                    a, b = m_rd.groups()[4], m_rd.groups()[5]
                    if mode in reads:
                        reads[mode][(stg, btch, ln)] = (a, b)
                    
                m_wr = re.search(r"\[(\d+)\] PPU_WRITE:\s+stage=(\d+)\s+wr_batch=(\d+)\s+lane=(\d+)\s+r0=([xXzZ\d]+)\s+r1=([xXzZ\d]+)", line)
                if m_wr:
                    mode, stg, btch, ln = map(int, m_wr.groups()[:4])
                    r0, r1 = m_wr.groups()[4], m_wr.groups()[5]
                    if mode in writes:
                        writes[mode][(stg, btch, ln)] = (r0, r1)
                        
                m_wr_r1 = re.search(r"\[(\d+)\] PPU_WRITE_R1:\s+stage=(\d+)\s+wr_batch=(\d+)\s+lane=(\d+)\s+r1=([xXzZ\d]+)", line)
                if m_wr_r1:
                    mode, stg, btch, ln = map(int, m_wr_r1.groups()[:4])
                    r1_val = m_wr_r1.groups()[4]
                    if mode in writes_r1:
                        writes_r1[mode][(stg, btch, ln)] = r1_val
    except: pass
    return reads, writes, writes_r1

def verify_ntt(mode, mode_name, golden_array, reads, writes, out):
    is_dil = (mode in [1, 3])
    NUM_STAGES = 8 if is_dil else 7
    is_intt = (mode in [2, 3])
    mod_q = Q_DIL if is_dil else Q
    t_array = twiddles_dil if is_dil else twiddles
    
    out.write(f"\n================ {mode_name} ================\n")
    
    for stage in range(NUM_STAGES):
        out.write(f"\n=== INTERMEDIATE STEPS FOR STAGE {stage} ===\n")
        k = 7 - stage
        length = 1 << k
        
        op_count = 0
        for batch in range(32):
            for lane in range(4):
                c = (batch << 2) + lane
                if is_intt:
                    stage_start_inv = (1 << (stage + 1)) - 1
                    sw_idx = stage_start_inv - (c >> k)
                else:
                    sw_idx = (1 << stage) + (c >> k)
                
                zeta = t_array[sw_idx]
                rd_log = reads.get((stage, batch, lane), None)
                wr_log = writes.get((stage, batch, lane), None)
                
                actual_a = c + ((c >> k) << k)
                actual_b = actual_a + length
                
                a_val = golden_array[actual_a]
                b_val = golden_array[actual_b]
                
                if is_intt:
                    r0 = (a_val + b_val) % mod_q
                    r1 = ((a_val - b_val + mod_q) * zeta) % mod_q
                else:
                    bz = (b_val * zeta) % mod_q
                    r0 = (a_val + bz) % mod_q
                    r1 = (a_val - bz + mod_q) % mod_q
                
                nb_a, off_a = new_mangling(actual_a)
                nb_b, off_b = new_mangling(actual_b)

                out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical A={actual_a}, B={actual_b}):\n")
                out.write(f"  [PYTHON EXPECTS READ ] : a={a_val} (From Bank={nb_a}, Offset={off_a}) | b={b_val} (From Bank={nb_b}, Offset={off_b})\n")
                out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}, r1={r1}\n")
                
                if rd_log and wr_log:
                    out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={rd_log[0]}, b={rd_log[1]} | PPU wrote r0={wr_log[0]}, r1={wr_log[1]}\n")
                else:
                    out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
                
                golden_array[actual_a] = r0
                golden_array[actual_b] = r1
                op_count += 1
                
def verify_basemul(golden_array_a, golden_array_b, reads, writes, out):
    out.write(f"\n================ BASEMUL ================\n")
    stage = 7
    op_count = 0
    for batch in range(32):
        for lane in range(4):
            addr = (batch << 2) + lane
            idx0 = addr * 2
            idx1 = addr * 2 + 1
            
            zeta = twiddles[64 + (addr >> 1)]
            
            a0 = golden_array_a[idx0]
            a1 = golden_array_a[idx1]
            b0 = golden_array_b[idx0]
            b1 = golden_array_b[idx1]
            
            r0 = (a0 * b0 + a1 * b1 * zeta) % Q
            r1 = (a0 * b1 + a1 * b0) % Q
            
            rd_log = reads.get((stage, batch, lane), None)
            wr_log = writes.get((stage, batch, lane), None)
            
            out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical idx0={idx0}, idx1={idx1}):\n")
            out.write(f"  [PYTHON EXPECTS READ ] : a0={a0}, a1={a1} | b0={b0}, b1={b1}\n")
            out.write(f"  [PYTHON EXPECTS CONCAT]: a={(a1 << 16) | a0}, b={(b1 << 16) | b0}\n")
            out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}, r1={r1}\n")
            
            if not rd_log and not wr_log:
                out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
            else:
                r_a, r_b = rd_log if rd_log else ("?","?")
                w_0, w_1 = wr_log if wr_log else ("?","?")
                out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={r_a}, b={r_b} | PPU wrote r0={w_0}, r1={w_1}\n")
                
            golden_array_a[idx0] = r0
            golden_array_a[idx1] = r1
            golden_array_b[idx0] = r0
            golden_array_b[idx1] = r1
            op_count += 1
            

def verify_scale(mode, mode_name, golden_array, reads, writes, out):
    out.write(f"\n================ {mode_name} ================\n")
    is_dil = (mode == 11)
    mod_q = Q_DIL if is_dil else Q
    inv_n = 8347681 if is_dil else 3303
    
    op_count = 0
    stage = 0
    for batch in range(64):
        for lane in range(4):
            c = (batch << 2) + lane
            bank = c % 8
            offset = c // 8
            
            xor_sum = ((offset >> 4) & 1) ^ ((offset >> 3) & 1) ^ ((offset >> 2) & 1) ^ ((offset >> 1) & 1) ^ (offset & 1)
            x_2 = (bank >> 2) ^ xor_sum
            logical_addr = (offset << 3) | (x_2 << 2) | (bank & 3)
            
            a_val = golden_array[logical_addr]
            r0 = (a_val * inv_n) % mod_q
            
            rd_log = reads.get((stage, batch, lane), None)
            wr_log = writes.get((stage, batch, lane), None)
            
            out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={logical_addr}):\n")
            out.write(f"  [PYTHON EXPECTS READ ] : a={a_val}\n")
            out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}\n")
            
            if not rd_log and not wr_log:
                out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
            else:
                r_a, r_b = rd_log if rd_log else ("?","?")
                w_0, w_1 = wr_log if wr_log else ("?","?")
                out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={r_a}, b={r_b} | PPU wrote r0={w_0}\n")
                
            golden_array[logical_addr] = r0
            op_count += 1

def verify_basemul_dil(golden_array_a, golden_array_b, reads, writes, out):
    out.write(f"\n================ BASEMUL DILITHIUM ================\n")
    stage = 0
    op_count = 0
    for batch in range(64):
        for lane in range(4):
            addr = (batch << 2) + lane
            
            a_val = golden_array_a[addr]
            b_val = golden_array_b[addr]
            
            r0 = (a_val * b_val) % Q_DIL
            
            rd_log = reads.get((stage, batch, lane), None)
            wr_log = writes.get((stage, batch, lane), None)
            
            out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={addr}):\n")
            out.write(f"  [PYTHON EXPECTS READ ] : a={a_val} | b={b_val}\n")
            out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}\n")
            
            if not rd_log and not wr_log:
                out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
            else:
                r_a, r_b = rd_log if rd_log else ("?","?")
                w_0, w_1 = wr_log if wr_log else ("?","?")
                out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={r_a}, b={r_b} | PPU wrote r0={w_0}\n")
                
            golden_array_a[addr] = r0
            op_count += 1

def verify_compress(golden_array, reads, writes, writes_r1, out, d=10):
    """Verify ML-KEM Compression: Compress_d(x) = ((x << d) * 5040 + 2^23) >> 24 & ((1 << d) - 1)
    
    Hardware iterates 33 batches (0-32) × 2 steps with ADDR_FLAT.
    Port_a reads coefficient at batch*4+lane (u stream, indices 0-131).
    Port_b reads coefficient at batch*4+lane+128 (v stream, indices 128-259).
    Step 0 writes r1 (compressed port_b), Step 1 writes r0 (compressed port_a).
    PPU_WRITE fires on step 1 (we_r0), PPU_WRITE_R1 fires on step 0 (we_r1 only).
    """
    out.write(f"\n================ COMPRESSION (d={d}) ================\n")
    
    op_count = 0
    stage = 0
    for batch in range(32):
        for lane in range(4):
            u_idx = (batch << 2) + lane        # port_a coefficient index (0-131)
            v_idx = u_idx + 128                 # port_b coefficient index (128-259)
            
            if u_idx >= 256:
                continue
            
            u_val = golden_array[u_idx]
            
            # Compression formula matching hardware shift-and-add
            shifted = u_val << d
            product = shifted * 5040
            r0 = ((product + (1 << 23)) >> 24) & ((1 << d) - 1)
            
            rd_log = reads.get((stage, batch, lane), None)
            wr_log = writes.get((stage, batch, lane), None)
            
            out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={u_idx}):\n")
            out.write(f"  [PYTHON EXPECTS READ ] : a={u_val}\n")
            out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}\n")
            
            if not rd_log and not wr_log:
                out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
            else:
                r_a, r_b = rd_log if rd_log else ("?","?")
                w_0, w_1 = wr_log if wr_log else ("?","?")
                out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={r_a}, b={r_b} | PPU wrote r0={w_0}\n")
                
            golden_array[u_idx] = r0
            op_count += 1
            
            # Also verify the v stream (port_b) via PPU_WRITE_R1
            if v_idx < 256:
                v_val = golden_array[v_idx]
                shifted_v = v_val << d
                product_v = shifted_v * 5040
                r1 = ((product_v + (1 << 23)) >> 24) & ((1 << d) - 1)
                
                wr_r1_log = writes_r1.get((stage, batch, lane), None)
                
                out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={v_idx} [v-stream]):\n")
                out.write(f"  [PYTHON EXPECTS READ ] : a={v_val}\n")
                out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r1}\n")
                
                if wr_r1_log:
                    out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a=?, b=? | PPU wrote r0={wr_r1_log}\n")
                elif wr_log:
                    # r1 data also captured in the PPU_WRITE line
                    out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a=?, b=? | PPU wrote r0={wr_log[1]}\n")
                else:
                    out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
                    
                golden_array[v_idx] = r1
                op_count += 1


def verify_decompress(golden_array, reads, writes, writes_r1, out, d=10):
    """Verify ML-KEM Decompression: Decompress_d(y) = (y * 3329 + 2^(d-1)) >> d
    
    Hardware iterates 33 batches (0-32) × 2 steps with ADDR_FLAT.
    Port_a reads coefficient at batch*4+lane (u stream, indices 0-131).
    Port_b reads coefficient at batch*4+lane+128 (v stream, indices 128-259).
    Step 0 writes r1 (decompressed port_b), Step 1 writes r0 (decompressed port_a).
    """
    out.write(f"\n================ DECOMPRESSION (d={d}) ================\n")
    
    Q_KYB = 3329
    op_count = 0
    stage = 0
    for batch in range(32):
        for lane in range(4):
            u_idx = (batch << 2) + lane        # port_a coefficient index (0-131)
            v_idx = u_idx + 128                 # port_b coefficient index (128-259)
            
            if u_idx >= 256:
                continue
            
            u_val = golden_array[u_idx]
            
            # Decompression formula matching hardware shift-and-add
            product = u_val * Q_KYB
            r0 = (product + (1 << (d - 1))) >> d
            
            rd_log = reads.get((stage, batch, lane), None)
            wr_log = writes.get((stage, batch, lane), None)
            
            out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={u_idx}):\n")
            out.write(f"  [PYTHON EXPECTS READ ] : a={u_val}\n")
            out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}\n")
            
            if not rd_log and not wr_log:
                out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
            else:
                r_a, r_b = rd_log if rd_log else ("?","?")
                w_0, w_1 = wr_log if wr_log else ("?","?")
                out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={r_a}, b={r_b} | PPU wrote r0={w_0}\n")
                
            golden_array[u_idx] = r0
            op_count += 1
            
            # Also verify the v stream (port_b) via PPU_WRITE_R1
            if v_idx < 256:
                v_val = golden_array[v_idx]
                product_v = v_val * Q_KYB
                r1 = (product_v + (1 << (d - 1))) >> d
                
                wr_r1_log = writes_r1.get((stage, batch, lane), None)
                
                out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={v_idx} [v-stream]):\n")
                out.write(f"  [PYTHON EXPECTS READ ] : a={v_val}\n")
                out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r1}\n")
                
                if wr_r1_log:
                    out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a=?, b=? | PPU wrote r0={wr_r1_log}\n")
                elif wr_log:
                    out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a=?, b=? | PPU wrote r0={wr_log[1]}\n")
                else:
                    out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
                    
                golden_array[v_idx] = r1
                op_count += 1


def verify_add(golden_array_a, golden_array_b, reads, writes, out):
    out.write("\n================ ADD =================\n")
    q = 3329 # Assuming Kyber for ADD/SUB right now
    mismatches = 0
    total = 0
    op_count = 0
    for batch in range(64):
        for lane in range(4):
            logical_addr = (batch << 2) + lane
            
            a_val = golden_array_a[logical_addr]
            b_val = golden_array_b[logical_addr]
            r0 = (a_val + b_val) % q
            
            key = (0, batch, lane)
            wr_log = writes.get(key, None)
            rd_log = reads.get(key, None)
            
            out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={logical_addr}):\n")
            out.write(f"  [PYTHON EXPECTS READ ] : a={a_val}, b={b_val}\n")
            out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}\n")
            
            if wr_log:
                if str(r0) == wr_log[0] or str(r0 - q) == wr_log[0]:
                    pass # Match
                else:
                    mismatches += 1
                r_a, r_b = rd_log if rd_log else ("?","?")
                w_0, w_1 = wr_log if wr_log else ("?","?")
                out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={r_a}, b={r_b} | PPU wrote r0={w_0}\n")
            else:
                out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
                mismatches += 1
            total += 1
            op_count += 1
    
    status = "PASSED ✓" if mismatches == 0 else "FAILED ✗"
    print(f"# [        ADD         ] : {total - mismatches:>4} / {total:>4} matches | {status}")
    out.write(f"ADD Complete. Mismatches: {mismatches} / {total}\n")

def verify_sub(golden_array_a, golden_array_b, reads, writes, out):
    out.write("\n================ SUB =================\n")
    q = 3329 # Assuming Kyber
    mismatches = 0
    total = 0
    op_count = 0
    for batch in range(64):
        for lane in range(4):
            logical_addr = (batch << 2) + lane
            
            a_val = golden_array_a[logical_addr]
            b_val = golden_array_b[logical_addr]
            r0 = (a_val - b_val) % q
            
            key = (0, batch, lane)
            wr_log = writes.get(key, None)
            rd_log = reads.get(key, None)
            
            out.write(f"Operation {op_count} (Batch {batch}, Lane {lane} | Logical addr={logical_addr}):\n")
            out.write(f"  [PYTHON EXPECTS READ ] : a={a_val}, b={b_val}\n")
            out.write(f"  [PYTHON GOLDEN MATH ]  : r0={r0}\n")
            
            if wr_log:
                if str(r0) == wr_log[0] or str(r0 - q) == wr_log[0]:
                    pass # Match
                else:
                    mismatches += 1
                r_a, r_b = rd_log if rd_log else ("?","?")
                w_0, w_1 = wr_log if wr_log else ("?","?")
                out.write(f"  [SV TESTBENCH LOG ]    : AGU fetched a={r_a}, b={r_b} | PPU wrote r0={w_0}\n")
            else:
                out.write(f"  [SV TESTBENCH LOG ]    : MISSING LOG DATA\n")
                mismatches += 1
            total += 1
            op_count += 1
    
    status = "PASSED ✓" if mismatches == 0 else "FAILED ✗"
    print(f"# [        SUB         ] : {total - mismatches:>4} / {total:>4} matches | {status}")
    out.write(f"SUB Complete. Mismatches: {mismatches} / {total}\n")

def main():


    print(f"Generating sequential analysis for FWD NTT -> BASEMUL -> INV NTT...")

    golden_array = [0] * 256
    try:
        with open("logical_in.txt", "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) == 2: golden_array[int(parts[0])] = int(parts[1])
    except: pass
    
    golden_array_b = list(golden_array)
    golden_array_copy = list(golden_array)
    
    all_reads, all_writes, all_writes_r1 = parse_logs()
    
    with open("detailed_stage_analysis.txt", "w") as out:
        reads = all_reads.get(0, {})
        writes = all_writes.get(0, {})
        if writes: verify_ntt(0, "FWD NTT (BUF_A0)", golden_array, reads, writes, out)
        
        #verify_ntt(0, "FWD NTT (BUF_B0)", golden_array_b, reads, writes, out)
        
        reads = all_reads.get(4, {})
        writes = all_writes.get(4, {})
        if writes: verify_basemul(golden_array, golden_array_b, reads, writes, out)
        
        reads = all_reads.get(2, {})
        writes = all_writes.get(2, {})
        if writes: verify_ntt(2, "INV NTT", golden_array_b, reads, writes, out)
        
        golden_array_add_a = [0] * 256
        golden_array_add_b = [0] * 256
        try:
            with open("logical_in_addsub_a.txt", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2: golden_array_add_a[int(parts[0])] = int(parts[1])
            with open("logical_in_addsub_b.txt", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2: golden_array_add_b[int(parts[0])] = int(parts[1])
        except: pass

        reads = all_reads.get(8, {})
        writes = all_writes.get(8, {})
        if writes: verify_add(golden_array_add_a, golden_array_add_b, reads, writes, out)
        
        reads = all_reads.get(9, {})
        writes = all_writes.get(9, {})
        if writes: verify_sub(golden_array_add_a, golden_array_add_b, reads, writes, out)

        
        reads = all_reads.get(10, {})
        writes = all_writes.get(10, {})
        if writes: verify_scale(10, "SCALE INTT", golden_array_b, reads, writes, out)
        
        golden_array_dil = list(golden_array_copy)
        
        reads = all_reads.get(1, {})
        writes = all_writes.get(1, {})
        if writes: verify_ntt(1, "FWD NTT DILITHIUM (BUF_A0)", golden_array_dil, reads, writes, out)
        
        reads = all_reads.get(3, {})
        writes = all_writes.get(3, {})
        if writes: verify_ntt(3, "INV NTT DILITHIUM (BUF_A0)", golden_array_dil, reads, writes, out)

        reads = all_reads.get(11, {})
        writes = all_writes.get(11, {})
        if writes: verify_scale(11, "SCALE INTT DILITHIUM", golden_array_dil, reads, writes, out)

        golden_array_seesaw_a = [0] * 256
        golden_array_seesaw_b = [0] * 256
        try:
            with open("logical_in_seesaw_a.txt", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2: golden_array_seesaw_a[int(parts[0])] = int(parts[1])
            with open("logical_in_seesaw_b.txt", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2: golden_array_seesaw_b[int(parts[0])] = int(parts[1])
        except: pass
        
        reads = all_reads.get(5, {})
        writes = all_writes.get(5, {})
        if writes: verify_basemul_dil(golden_array_seesaw_a, golden_array_seesaw_b, reads, writes, out)
        
        # Compression verification
        golden_array_comp = [0] * 256
        try:
            with open("logical_in_comp.txt", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2: golden_array_comp[int(parts[0])] = int(parts[1])
        except: pass
        
        reads = all_reads.get(6, {})
        writes = all_writes.get(6, {})
        writes_r1_comp = all_writes_r1.get(6, {})
        if writes_r1_comp: verify_compress(golden_array_comp, reads, writes, writes_r1_comp, out, d=10)
        
        # Decompression verification
        golden_array_decomp = [0] * 256
        try:
            with open("logical_in_decomp.txt", "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2: golden_array_decomp[int(parts[0])] = int(parts[1])
        except: pass
        
        reads = all_reads.get(7, {})
        writes = all_writes.get(7, {})
        writes_r1_decomp = all_writes_r1.get(7, {})
        if writes: verify_decompress(golden_array_decomp, reads, writes, writes_r1_decomp, out, d=10)
                    
    print("Done! Open 'detailed_stage_analysis.txt' to view the trace.")

if __name__ == "__main__":
    main()
