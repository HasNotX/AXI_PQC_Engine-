package agu_pkg;

    // =========================================================================
    // BUFFER IDENTIFIERS (3-bit)
    // Used by the crossbar to route data to the correct logical memory spaces
    // =========================================================================
    typedef enum logic [2:0] {
        BUF_A0   = 3'b000,  // Maps to top 32 words of A-side physical banks
        BUF_A1   = 3'b001,  // Maps to bottom 32 words of A-side physical banks
        BUF_B0   = 3'b010,  // Maps to top 32 words of B-side physical banks
        BUF_B1   = 3'b011,  // Maps to bottom 32 words of B-side physical banks
        BUF_NULL = 3'b100   // Disconnects the unit (Idle state)
    } buffer_id_e;

    // =========================================================================
    // ADDRESSING MODES (2-bit)
    // Used by the Address Mapper to calculate the physical sub-bank and offset
    // =========================================================================
    typedef enum logic [1:0] {
        ADDR_FLAT   = 2'd0, // Linear mapping (used by DMA, PGU, and simple PPU steps)
        ADDR_XOR    = 2'd1, // Conflict-free mapping (for NTT/INTT butterflies)
        ADDR_CONCAT = 2'd2, // 16-bit coefficient packing (for Base Multiplication)
        ADDR_SEESAW = 2'd3  // Seesaw mapping for conflict-free Dilithium Base Multiplication
    } addr_mode_e;

endpackage : agu_pkg