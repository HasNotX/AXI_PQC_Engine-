module unified_hash_engine_top
  import unified_hash_engine_pkg::*;
(
  input  logic         clk_i,
  input  logic         rst_i,

  // Software CSR bus
  input  logic         csr_wr_en_i,
  input  logic         csr_rd_en_i,
  input  logic [7:0]   csr_addr_i,
  input  logic [31:0]  csr_wdata_i,
  output logic [31:0]  csr_rdata_o,
  output logic         csr_rvalid_o,

  // External AGU / ping-pong memory boundary
  output logic         agu_valid_o,
  input  logic         agu_ready_i,
  output logic [47:0]  agu_data_o,
  output logic [1:0]   agu_lane_valid_o,

  output logic [4:0]   agu_coefficient_count_o,
  output logic [8:0]   agu_word_index_o,
  output logic         agu_buffer_sel_o,
  output logic         agu_poly_start_o,
  input  logic         agu_poly_done_i,
  input  logic         agu_overflow_i,
  input  logic [31:0]  agu_current_addr_i,

  output engine_status_e status_o,
  output logic           busy_o,
  output logic           done_o,
  output logic           error_o
);

  // ========================================================================
  // Control-plane signals
  // ========================================================================

  logic start_pulse;
  logic start_accept;
  operation_t csr_op;
  logic int_clear;
  logic poly_valid;
  logic error_invalid_config;
  logic error_fifo_protocol;
  logic error_memory_overflow;
  logic [POLY_INDEX_W-1:0] current_poly;

  logic msg_start;
  operation_t msg_op;
  logic msg_busy;
  logic msg_done;
  logic msg_error;
  logic [MAX_SEED_W+16-1:0] message;
  logic [6:0] message_len_bytes;

  logic pad_start;
  logic pad_busy;
  logic pad_done;
  logic pad_error;
  keccak_state_t padded_block;

  logic keccak_cmd_valid;
  logic keccak_cmd_ready;
  keccak_cmd_e keccak_cmd;
  logic keccak_busy;
  logic keccak_done;
  logic keccak_error;
  keccak_state_t keccak_state;

  logic tap_start;
  logic tap_busy;
  logic tap_done;
  logic tap_error;

  logic entropy_fifo_clear;
  logic bitreader_clear;
  logic entropy_protocol_error;

  logic sampler_start;
  logic sampler_resume;
  operation_t sampler_op;
  sampler_params_t sampler_params;
  sampler_status_e sampler_status;
  logic sampler_busy;
  logic sampler_done;
  logic sampler_error;

  logic packer_start;
  logic packer_busy;
  logic packer_done;
  logic packer_error;

  logic memory_poly_start;
  logic agu_poly_done_pending_q;
  logic [31:0] current_addr_fsm;

  // ========================================================================
  // Entropy datapath
  // ========================================================================

  logic entropy_push_valid;
  logic entropy_push_ready;
  logic [63:0] entropy_push_data;
  logic entropy_pop_valid;
  logic entropy_pop_ready;
  logic [63:0] entropy_pop_data;

  logic entropy_take_valid;
  logic entropy_take_ready;
  logic [6:0] entropy_take_nbits;
  logic [63:0] entropy_take_data;
  logic entropy_need_refill;
  logic entropy_reservoir_error;

  logic candidate_valid;
  logic candidate_ready;
  logic [95:0] candidate_bits;
  logic sign_valid;
  logic sign_ready;
  logic [63:0] sign_bits;
  logic position_valid;
  logic position_ready;
  logic [7:0] position_bits;

  typedef enum logic [1:0] {
    ENTROPY_NONE = 2'd0,
    ENTROPY_CANDIDATE = 2'd1,
    ENTROPY_SIGN = 2'd2,
    ENTROPY_POSITION = 2'd3
  } entropy_request_e;

  entropy_request_e entropy_request_type;
  logic sign_word_loaded_q;

  logic packer_packet_valid;
  logic packer_packet_ready;
  logic [47:0] packer_packet_data;
  logic [1:0] packer_packet_lane_valid;
  logic [4:0] packer_packet_coefficient_count;
  logic [8:0] packer_packet_word_index;
  logic [1:0] coefficient_valid;
  logic coefficient_ready;
  logic [47:0] coefficient;
  logic [8:0] coefficient_index;

  logic output_valid;
  logic output_ready;
  logic [47:0] output_data;
  logic [1:0] output_lane_valid;
  logic [4:0] output_coefficient_count;
  logic [5:0] output_count;
  logic output_empty;
  logic output_full;
  logic [8:0] agu_word_index_q;

  function automatic logic is_sample_ball(input operation_t op);
    return (op.algo == ALGO_MLDSA) && (op.dist_type == DIST_SAMPLE_BALL);
  endfunction

  function automatic logic [6:0] request_width(input sampler_params_t params);
    return params.entropy_bits_per_candidate * params.parallel_lanes;
  endfunction

  // The reservoir presents one entropy group directly when enough bits are
  // available. This replaces the old request/refill/response state machine.
  always_comb begin
    entropy_take_valid = 1'b0;
    entropy_take_nbits = 7'd0;
    entropy_request_type = ENTROPY_NONE;

    if (sampler_busy) begin
      if (is_sample_ball(sampler_op)) begin
        if ((!sign_word_loaded_q && sign_ready) ||
            (sign_word_loaded_q && position_ready)) begin
          entropy_take_valid = 1'b1;
          entropy_take_nbits = sign_word_loaded_q ? 7'd8 : 7'd64;
          entropy_request_type = sign_word_loaded_q ?
                                 ENTROPY_POSITION : ENTROPY_SIGN;
        end
      end else if (candidate_ready) begin
        entropy_take_valid = 1'b1;
        entropy_take_nbits = request_width(sampler_params);
        entropy_request_type = ENTROPY_CANDIDATE;
      end
    end
  end

  assign candidate_valid = entropy_take_valid && entropy_take_ready &&
                           (entropy_request_type == ENTROPY_CANDIDATE);
  assign candidate_bits  = {{32{1'b0}}, entropy_take_data};

  assign sign_valid = entropy_take_valid && entropy_take_ready &&
                      (entropy_request_type == ENTROPY_SIGN);
  assign sign_bits  = entropy_take_data;

  assign position_valid = entropy_take_valid && entropy_take_ready &&
                          (entropy_request_type == ENTROPY_POSITION);
  assign position_bits  = entropy_take_data[7:0];

  always_ff @(posedge clk_i) begin
    if (rst_i || sampler_start) begin
      sign_word_loaded_q      <= 1'b0;
    end else begin
      if (sign_valid && sign_ready)
        sign_word_loaded_q <= 1'b1;
    end
  end

  // ========================================================================
  // Control modules
  // ========================================================================

  csr_file u_csr_file (
    .clk(clk_i), 
    .rst(rst_i),
    
    .csr_wr_en(csr_wr_en_i), 
    .csr_rd_en(csr_rd_en_i),
    
    .csr_addr(csr_addr_i), 
    .csr_wdata(csr_wdata_i),
    
    .csr_rdata(csr_rdata_o), 
    .csr_rvalid(csr_rvalid_o),
    
    .start_pulse(start_pulse), 
    .start_accept(start_accept), 
    .op_cfg(csr_op),
    
    .status_i(status_o), 
    .poly_valid_i(poly_valid),
    
    .error_invalid_config_i(error_invalid_config),
    
    .error_fifo_protocol_i(error_fifo_protocol),
    
    .error_memory_overflow_i(error_memory_overflow),
    
    .current_poly_i(current_poly), 
    .current_addr_i(current_addr_fsm),
    
    .int_clear_pulse(int_clear)
  );

  main_fsm u_main_fsm (
    
    .clk(clk_i), 
    .rst(rst_i),
    
    .start_req_i(start_pulse), 
    .start_accept_o(start_accept),
    
    .op_cfg_i(csr_op), 
    .int_clear_i(int_clear),
    
    .status_o(status_o), 
    .poly_valid_o(poly_valid),
    
    .error_invalid_config_o(error_invalid_config),
    
    .error_fifo_protocol_o(error_fifo_protocol),
    
    .error_memory_overflow_o(error_memory_overflow),
    
    .current_poly_o(current_poly), 
    .current_addr_i(agu_current_addr_i),
    
    .msg_start_o(msg_start), 
    .msg_op_o(msg_op), 
    .msg_busy_i(msg_busy),
    
    .msg_done_i(msg_done), 
    .msg_error_i(msg_error),
    
    .pad_start_o(pad_start), 
    .pad_busy_i(pad_busy), 
    .pad_done_i(pad_done),
    
    .pad_error_i(pad_error),
    
    .keccak_cmd_valid_o(keccak_cmd_valid),
    
    .keccak_cmd_ready_i(keccak_cmd_ready), 
    .keccak_cmd_o(keccak_cmd),
    
    .keccak_busy_i(keccak_busy), 
    .keccak_done_i(keccak_done),
    
    .keccak_error_i(keccak_error),
    
    .tap_start_o(tap_start), 
    .tap_busy_i(tap_busy), 
    .tap_done_i(tap_done),
    
    .tap_error_i(tap_error),
    
    .entropy_fifo_clear_o(entropy_fifo_clear),
    
    .bitreader_clear_o(bitreader_clear),
    
    .entropy_protocol_error_i(entropy_protocol_error),
    
    .sampler_start_o(sampler_start), 
    .sampler_resume_o(sampler_resume),
    
    .sampler_op_o(sampler_op), 
    .sampler_params_o(sampler_params),
    
    .sampler_status_i(sampler_status), 
    .sampler_error_i(sampler_error),
    
    .packer_start_o(packer_start), 
    .packer_busy_i(packer_busy),
    
    .packer_done_i(packer_done), 
    .packer_error_i(packer_error),
    
    .memory_poly_start_o(memory_poly_start),
    
    .memory_poly_done_i(agu_poly_done_pending_q),
    
    .memory_overflow_i(agu_overflow_i),
    
    .current_addr_o(current_addr_fsm)
  );

  message_formatter u_message_formatter (
    
    .clk(clk_i), 
    .rst(rst_i), 
    .start_i(msg_start), 
    .op_i(msg_op),
    
    .busy_o(msg_busy), 
    .done_o(msg_done), 
    .error_o(msg_error),
    
    .message_o(message), 
    .message_len_bytes_o(message_len_bytes)
  );

  padded_block_builder u_padded_block_builder (
    
    .clk(clk_i), 
    .rst(rst_i), 
    .start_i(pad_start),
    
    .mode_i(msg_op.mode), 
    .message_i(message),
    
    .message_len_bytes_i(message_len_bytes),
    
    .busy_o(pad_busy), 
    .done_o(pad_done), 
    .error_o(pad_error),
    
    .block_o(padded_block)
  );

  keccak_core u_keccak_core (
    
    .clk(clk_i), 
    .rst(rst_i),
    
    .cmd_valid_i(keccak_cmd_valid), 
    .cmd_ready_o(keccak_cmd_ready),
    
    .cmd_i(keccak_cmd), 
    .mode_i(msg_op.mode),
    
    .absorb_block_i(padded_block), 
    .busy_o(keccak_busy),
    
    .done_o(keccak_done), 
    .error_o(keccak_error), 
    .state_o(keccak_state)
  );

  iotap_64 u_iotap_64 (
    
    .clk_i(clk_i), 
    .rst_i(rst_i), 
    .start_i(tap_start),
    
    .mode_i(msg_op.mode), 
    .keccak_state_i(keccak_state),
    
    .push_valid_o(entropy_push_valid), 
    .push_ready_i(entropy_push_ready),
    
    .push_data_o(entropy_push_data), 
    .busy_o(tap_busy),
    
    .done_o(tap_done), 
    .error_o(tap_error)
  );

  entropy_fifo_64x32 u_entropy_fifo (
    
    .clk_i(clk_i), 
    .rst_i(rst_i | entropy_fifo_clear),
    
    .push_valid_i(entropy_push_valid), 
    .push_ready_o(entropy_push_ready),
    
    .push_data_i(entropy_push_data), 
    .pop_valid_o(entropy_pop_valid),
    
    .pop_ready_i(entropy_pop_ready), 
    .pop_data_o(entropy_pop_data),
    
    .empty_o(), 
    .full_o(), 
    .count_o()
  );

  entropy_reservoir_128 u_entropy_reservoir (
    .clk_i(clk_i),
    .rst_i(rst_i | bitreader_clear),
    .take_valid_i(entropy_take_valid),
    .take_ready_o(entropy_take_ready),
    .take_nbits_i(entropy_take_nbits),
    .take_data_o(entropy_take_data),
    .fifo_pop_valid_i(entropy_pop_valid),
    .fifo_pop_ready_o(entropy_pop_ready),
    .fifo_pop_data_i(entropy_pop_data),
    .need_refill_o(entropy_need_refill),
    .error_o(entropy_reservoir_error)
  );

  sampler_unit_2lane u_sampler_unit (
    
    .clk_i(clk_i), 
    .rst_i(rst_i), 
    .start_i(sampler_start),
    
    .op_i(sampler_op), 
    .params_i(sampler_params), 
    .busy_o(sampler_busy),
    
    .done_o(sampler_done), 
    .error_o(sampler_error),
    
    .candidate_valid_i(candidate_valid), 
    .candidate_ready_o(candidate_ready),
    
    .candidate_bits_i(candidate_bits), 
    .sign_valid_i(sign_valid),
    
    .sign_ready_o(sign_ready), 
    .sign_bits_i(sign_bits),
    
    .position_valid_i(position_valid), 
    .position_ready_o(position_ready),
    
    .position_i(position_bits), 
    .coefficient_valid_o(coefficient_valid),
    
    .coefficient_ready_i(coefficient_ready), 
    .coefficient_o(coefficient),
    
    .coefficient_index_o(coefficient_index)
  );

  assign sampler_status = entropy_reservoir_error || sampler_error ? SAMP_ERROR :
                          sampler_done ? SAMP_DONE :
                          (sampler_busy && entropy_need_refill) ?
                            SAMP_NEED_MORE_ENTROPY :
                          sampler_busy ? SAMP_BUSY : SAMP_IDLE;

  coefficient_packer_2lane u_coefficient_packer (
    
    .clk_i(clk_i), 
    .rst_i(rst_i), 
    .start_i(packer_start),
    
    .algo_i(sampler_op
      .algo), 
    .dist_type_i(sampler_op
      .dist_type),
    
    .coefficient_valid_i(coefficient_valid),
    
    .coefficient_ready_o(coefficient_ready), 
    .coefficient_i(coefficient),
    
    .coefficient_index_i(coefficient_index),
    
    .packet_valid_o(packer_packet_valid), 
    .packet_ready_i(packer_packet_ready),
    
    .packet_data_o(packer_packet_data), 
    .packet_lane_valid_o(packer_packet_lane_valid),
    .packet_coefficient_count_o(packer_packet_coefficient_count),
    .packet_word_index_o(packer_packet_word_index),
    
    .poly_words_done_o(packer_done), 
    .busy_o(packer_busy),
    
    .error_o(packer_error)
  );

  output_fifo_48x32 u_output_fifo (
    
    .clk_i(clk_i), 
    .rst_i(rst_i),
    
    .push_valid_i(packer_packet_valid), 
    .push_ready_o(packer_packet_ready),
    
    .push_data_i(packer_packet_data),
    .push_lane_valid_i(packer_packet_lane_valid),
    .push_coefficient_count_i(packer_packet_coefficient_count),
    .pop_valid_o(output_valid), 
    
    .pop_ready_i(output_ready), 
    .pop_data_o(output_data),
    .pop_lane_valid_o(output_lane_valid),
    .pop_coefficient_count_o(output_coefficient_count),
    
    .empty_o(output_empty), 
    .full_o(output_full), 
    .count_o(output_count)
  );

  assign output_ready = agu_ready_i;
  assign agu_valid_o = output_valid;
  assign agu_data_o = output_data;
  assign agu_lane_valid_o = output_lane_valid;
  assign agu_coefficient_count_o = output_coefficient_count;
  assign agu_word_index_o = agu_word_index_q;
  assign agu_buffer_sel_o = sampler_op.buffer_sel;
  assign agu_poly_start_o = memory_poly_start;
  assign entropy_protocol_error = entropy_reservoir_error;
  assign busy_o = (status_o == STATUS_BUSY);
  assign done_o = (status_o == STATUS_DONE);
  assign error_o = (status_o == STATUS_ERROR);

  // The output FIFO can drain before the main FSM reaches ST_WAIT_MEMORY.
  // Preserve the AGU's one-cycle completion pulse until this polynomial is
  // retired; memory_poly_start clears it for the following polynomial.
  always_ff @(posedge clk_i) begin
    if (rst_i || memory_poly_start)
      agu_poly_done_pending_q <= 1'b0;
    else if (agu_poly_done_i)
      agu_poly_done_pending_q <= 1'b1;
  end

  always_ff @(posedge clk_i) begin
    if (rst_i || memory_poly_start)
      agu_word_index_q <= '0;
    else if (output_valid && output_ready)
      agu_word_index_q <= agu_word_index_q + output_coefficient_count;
  end

endmodule : unified_hash_engine_top
