import sys
import re

def main():
    filename = "detailed_stage_analysis.txt"
    try:
        with open(filename, "r") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: {filename} not found.")
        return

    # Split into operation blocks
    blocks = re.split(r"(?=Operation\s+\d+)", content)
    
    total_operations = 0
    math_vs_sram_matches = 0
    missing_logs = 0

    for block in blocks:
        if not block.strip() or not block.startswith("Operation"):
            continue

        total_operations += 1

        # Extract Golden Values & Physical SRAM Writes
        m_golden = re.search(r"\[PYTHON GOLDEN MATH \]\s*:\s*r0=(\d+),\s*r1=(\d+)", block)
        m_writes = re.search(r"\[SV PHYSICAL WRITES \]\s*:\s*Wrote out_a=(\d+)\s*\|\s*Wrote out_b=(\d+)", block)

        if "MISSING LOG DATA" in block:
            missing_logs += 1

        if m_golden and m_writes:
            exp_r0, exp_r1 = int(m_golden.group(1)), int(m_golden.group(2))
            out_a, out_b = int(m_writes.group(1)), int(m_writes.group(2))

            if exp_r0 == out_a and exp_r1 == out_b:
                math_vs_sram_matches += 1

    print("==================================================")
    print("              MATCH VERIFICATION SUMMARY          ")
    print("==================================================")
    print(f"Total Operations Analyzed: {total_operations}")
    print(f"-> Math vs Physical SRAM:     {math_vs_sram_matches} / {total_operations}")
    
    if missing_logs > 0:
        print(f"\n[INFO] {missing_logs}/{total_operations} operations contain 'MISSING LOG DATA'.")
        print("       (Hardware verification relies on Physical SRAM Writes).")

    if math_vs_sram_matches == total_operations and total_operations > 0:
        print("\nSUCCESS: Physical SRAM values match Python Golden Model perfectly! 🎉")
    else:
        print(f"\nFAILURE: {total_operations - math_vs_sram_matches} mismatches detected in SRAM writes. ❌")

if __name__ == "__main__":
    main()