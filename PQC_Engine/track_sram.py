import re

bank = 0
offset = 30
val_b0 = None
val_b4 = None

with open("sim_transcript.log") as f:
    for line in f:
        # We need to parse PPU_WRITE and deduce the physical address, but it is hard.
        # Alternatively, we can check the golden arrays.
        pass
