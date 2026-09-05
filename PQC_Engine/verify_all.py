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

    # Split into sections based on '================'
    sections = re.split(r"================\s+(.*?)\s+================", content)
    
    if len(sections) < 3:
        print("Could not find sections in the log file.")
        return

    print("==================================================")
    print("              MATCH VERIFICATION SUMMARY          ")
    print("==================================================")
    
    total_ops = 0
    total_matches = 0

    # sections[0] is everything before the first '================'
    # sections[1] is the name of the first section (e.g., 'FWD NTT (BUF_A0)')
    # sections[2] is the content of the first section
    for i in range(1, len(sections), 2):
        section_name = sections[i].strip()
        section_content = sections[i+1]
        
        blocks = re.split(r"(?=Operation\s+\d+)", section_content)
        
        sec_ops = 0
        sec_matches = 0
        
        for block in blocks:
            if not block.strip() or not block.startswith("Operation"):
                continue
                
            sec_ops += 1
            

            m_golden = re.search(r"\[PYTHON GOLDEN MATH \]\s*:\s*r0=(\d+)(?:,\s*r1=(\d+))?", block)
            m_sv = re.search(r"\[SV TESTBENCH LOG \].*?PPU wrote r0=(\d+|\?)(?:,\s*r1=(\d+|\?))?", block)
            
            if m_golden and m_sv:
                exp_r0 = m_golden.group(1)
                exp_r1 = m_golden.group(2)
                sv_r0 = m_sv.group(1)
                sv_r1 = m_sv.group(2)
                
                match = True
                if exp_r0 != sv_r0: match = False
                if exp_r1 is not None and exp_r1 != sv_r1: match = False
                if exp_r1 is None and sv_r1 is not None: match = False
                
                if match:
                    sec_matches += 1

                    
        total_ops += sec_ops
        total_matches += sec_matches
        
        status = "PASSED 🎉" if sec_ops > 0 and sec_matches == sec_ops else f"FAILED ❌ ({sec_ops - sec_matches} mismatches)"
        print(f"[{section_name:^20}] : {sec_matches:4d} / {sec_ops:4d} matches | {status}")

    print("==================================================")
    if total_ops > 0 and total_matches == total_ops:
        print(f"SUCCESS: All {total_ops} operations match perfectly! 🏆")
    else:
        print(f"FAILURE: {total_ops - total_matches} out of {total_ops} total operations have mismatches. ❌")

if __name__ == "__main__":
    main()
