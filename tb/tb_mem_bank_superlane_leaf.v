`timescale 1ns/1ps

module tb_mem_bank_superlane_leaf;

    localparam [2:0] OPCODE_READ  = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;

    localparam [1:0] FAULT_NONE           = 2'd0;
    localparam [1:0] FAULT_ILLEGAL_OPCODE = 2'd1;
    localparam [1:0] FAULT_READ_PRESERVE  = 2'd2;
    localparam [1:0] FAULT_INVALID_WRITE  = 2'd3;

    reg         clk_i;
    reg         rst_ni;
    reg         cmd_valid_i;
    reg  [2:0]  cmd_opcode_i;
    reg  [14:0] cmd_row_i;
    reg         cmd_stream_dir_i;
    reg  [4:0]  cmd_stream_idx_i;
    reg         cmd_preserve_i;
    reg         stream_valid_i;
    reg  [63:0] stream_data_i;

    wire        stream_consume_o;
    wire        read_valid_o;
    wire [63:0] read_data_o;
    wire        read_stream_dir_o;
    wire [4:0]  read_stream_idx_o;
    wire        fault_valid_o;
    wire [1:0]  fault_code_o;

    integer errors;

    mem_bank_superlane_leaf dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cmd_valid_i(cmd_valid_i),
        .cmd_opcode_i(cmd_opcode_i),
        .cmd_row_i(cmd_row_i),
        .cmd_stream_dir_i(cmd_stream_dir_i),
        .cmd_stream_idx_i(cmd_stream_idx_i),
        .cmd_preserve_i(cmd_preserve_i),
        .stream_valid_i(stream_valid_i),
        .stream_data_i(stream_data_i),
        .stream_consume_o(stream_consume_o),
        .read_valid_o(read_valid_o),
        .read_data_o(read_data_o),
        .read_stream_dir_o(read_stream_dir_o),
        .read_stream_idx_o(read_stream_idx_o),
        .fault_valid_o(fault_valid_o),
        .fault_code_o(fault_code_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    task clear_inputs;
        begin
            cmd_valid_i      = 1'b0;
            cmd_opcode_i     = OPCODE_READ;
            cmd_row_i        = 15'b0;
            cmd_stream_dir_i = 1'b0;
            cmd_stream_idx_i = 5'b0;
            cmd_preserve_i   = 1'b0;
            stream_valid_i   = 1'b0;
            stream_data_i    = 64'b0;
        end
    endtask

    task apply_command;
        input [2:0]  opcode;
        input [14:0] row;
        input        direction;
        input [4:0]  stream_index;
        input        preserve;
        input        stream_valid;
        input [63:0] stream_data;
        begin
            @(negedge clk_i);
            cmd_valid_i      = 1'b1;
            cmd_opcode_i     = opcode;
            cmd_row_i        = row;
            cmd_stream_dir_i = direction;
            cmd_stream_idx_i = stream_index;
            cmd_preserve_i   = preserve;
            stream_valid_i   = stream_valid;
            stream_data_i    = stream_data;
            @(posedge clk_i);
            #1;
            clear_inputs();
        end
    endtask

    task check_events;
        input       expected_consume;
        input       expected_read;
        input       expected_fault;
        input [1:0] expected_fault_code;
        input [8*48-1:0] test_name;
        begin
            if (stream_consume_o !== expected_consume) begin
                $display("ERROR %0s consume expected=%0d actual=%0d",
                         test_name, expected_consume, stream_consume_o);
                errors = errors + 1;
            end
            if (read_valid_o !== expected_read) begin
                $display("ERROR %0s read_valid expected=%0d actual=%0d",
                         test_name, expected_read, read_valid_o);
                errors = errors + 1;
            end
            if (fault_valid_o !== expected_fault) begin
                $display("ERROR %0s fault_valid expected=%0d actual=%0d",
                         test_name, expected_fault, fault_valid_o);
                errors = errors + 1;
            end
            if (expected_fault && fault_code_o !== expected_fault_code) begin
                $display("ERROR %0s fault_code expected=%0d actual=%0d",
                         test_name, expected_fault_code, fault_code_o);
                errors = errors + 1;
            end
        end
    endtask

    task check_read;
        input [63:0] expected_data;
        input        expected_direction;
        input [4:0]  expected_stream_index;
        input [8*48-1:0] test_name;
        begin
            if (read_data_o !== expected_data) begin
                $display("ERROR %0s read_data expected=%h actual=%h",
                         test_name, expected_data, read_data_o);
                errors = errors + 1;
            end
            if (read_stream_dir_o !== expected_direction) begin
                $display("ERROR %0s direction expected=%0d actual=%0d",
                         test_name, expected_direction, read_stream_dir_o);
                errors = errors + 1;
            end
            if (read_stream_idx_o !== expected_stream_index) begin
                $display("ERROR %0s stream_idx expected=%0d actual=%0d",
                         test_name, expected_stream_index, read_stream_idx_o);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b1;
        clear_inputs();

        $display("RUN_TEST reset_control_outputs");
        #2;
        rst_ni = 1'b0;
        #1;
        check_events(1'b0, 1'b0, 1'b0, FAULT_NONE,
                     "reset_control_outputs");
        @(negedge clk_i);
        rst_ni = 1'b1;
        @(posedge clk_i);
        #1;
        check_events(1'b0, 1'b0, 1'b0, FAULT_NONE,
                     "reset_release");

        $display("RUN_TEST valid_normal_write");
        apply_command(OPCODE_WRITE, 15'd10, 1'b0, 5'd0, 1'b0, 1'b1,
                      64'h1122334455667788);
        check_events(1'b1, 1'b0, 1'b0, FAULT_NONE,
                     "valid_normal_write");

        $display("RUN_TEST read");
        apply_command(OPCODE_READ, 15'd10, 1'b1, 5'd17, 1'b0, 1'b0, 64'b0);
        check_events(1'b0, 1'b1, 1'b0, FAULT_NONE, "read");
        check_read(64'h1122334455667788, 1'b1, 5'd17, "read");

        $display("RUN_TEST read_after_write");
        apply_command(OPCODE_WRITE, 15'd20, 1'b0, 5'd0, 1'b0, 1'b1,
                      64'hA5A55A5A12345678);
        check_events(1'b1, 1'b0, 1'b0, FAULT_NONE,
                     "raw_write_cycle_c");
        // This command is sampled on the immediately following active edge.
        apply_command(OPCODE_READ, 15'd20, 1'b0, 5'd9, 1'b0, 1'b0, 64'b0);
        check_events(1'b0, 1'b1, 1'b0, FAULT_NONE,
                     "raw_read_cycle_c_plus_1");
        check_read(64'hA5A55A5A12345678, 1'b0, 5'd9,
                   "raw_read_cycle_c_plus_1");

        $display("RUN_TEST invalid_normal_write");
        apply_command(OPCODE_WRITE, 15'd30, 1'b0, 5'd0, 1'b0, 1'b1,
                      64'h0102030405060708);
        apply_command(OPCODE_WRITE, 15'd30, 1'b0, 5'd0, 1'b0, 1'b0,
                      64'hDEADBEEFDEADBEEF);
        check_events(1'b0, 1'b0, 1'b1, FAULT_INVALID_WRITE,
                     "invalid_normal_write");
        apply_command(OPCODE_READ, 15'd30, 1'b0, 5'd3, 1'b0, 1'b0, 64'b0);
        check_events(1'b0, 1'b1, 1'b0, FAULT_NONE,
                     "invalid_write_storage_check");
        check_read(64'h0102030405060708, 1'b0, 5'd3,
                   "invalid_write_storage_check");

        $display("RUN_TEST valid_writetap");
        apply_command(OPCODE_WRITE, 15'd40, 1'b0, 5'd0, 1'b1, 1'b1,
                      64'hCAFEBABE89ABCDEF);
        check_events(1'b0, 1'b0, 1'b0, FAULT_NONE, "valid_writetap");
        apply_command(OPCODE_READ, 15'd40, 1'b1, 5'd12, 1'b0, 1'b0, 64'b0);
        check_events(1'b0, 1'b1, 1'b0, FAULT_NONE,
                     "valid_writetap_readback");
        check_read(64'hCAFEBABE89ABCDEF, 1'b1, 5'd12,
                   "valid_writetap_readback");

        $display("RUN_TEST invalid_writetap");
        apply_command(OPCODE_WRITE, 15'd40, 1'b0, 5'd0, 1'b1, 1'b0,
                      64'hFFFFFFFFFFFFFFFF);
        check_events(1'b0, 1'b0, 1'b0, FAULT_NONE, "invalid_writetap");
        apply_command(OPCODE_READ, 15'd40, 1'b0, 5'd13, 1'b0, 1'b0, 64'b0);
        check_events(1'b0, 1'b1, 1'b0, FAULT_NONE,
                     "invalid_writetap_storage_check");
        check_read(64'hCAFEBABE89ABCDEF, 1'b0, 5'd13,
                   "invalid_writetap_storage_check");

        $display("RUN_TEST unsupported_opcode");
        apply_command(3'b101, 15'd40, 1'b0, 5'd0, 1'b0, 1'b1,
                      64'h0BAD0BAD0BAD0BAD);
        check_events(1'b0, 1'b0, 1'b1, FAULT_ILLEGAL_OPCODE,
                     "unsupported_opcode");
        apply_command(OPCODE_READ, 15'd40, 1'b0, 5'd14, 1'b0, 1'b0, 64'b0);
        check_events(1'b0, 1'b1, 1'b0, FAULT_NONE,
                     "unsupported_opcode_storage_check");
        check_read(64'hCAFEBABE89ABCDEF, 1'b0, 5'd14,
                   "unsupported_opcode_storage_check");

        $display("RUN_TEST read_preserve_illegal");
        apply_command(OPCODE_READ, 15'd40, 1'b1, 5'd15, 1'b1, 1'b0, 64'b0);
        check_events(1'b0, 1'b0, 1'b1, FAULT_READ_PRESERVE,
                     "read_preserve_illegal");

        $display("RUN_TEST independent_rows");
        apply_command(OPCODE_WRITE, 15'd100, 1'b0, 5'd0, 1'b0, 1'b1,
                      64'h1000100010001000);
        apply_command(OPCODE_WRITE, 15'd101, 1'b0, 5'd0, 1'b0, 1'b1,
                      64'h2000200020002000);
        apply_command(OPCODE_WRITE, 15'd102, 1'b0, 5'd0, 1'b0, 1'b1,
                      64'h3000300030003000);
        apply_command(OPCODE_READ, 15'd100, 1'b0, 5'd1, 1'b0, 1'b0, 64'b0);
        check_read(64'h1000100010001000, 1'b0, 5'd1,
                   "independent_row_100");
        apply_command(OPCODE_READ, 15'd101, 1'b0, 5'd2, 1'b0, 1'b0, 64'b0);
        check_read(64'h2000200020002000, 1'b0, 5'd2,
                   "independent_row_101");
        apply_command(OPCODE_READ, 15'd102, 1'b0, 5'd3, 1'b0, 1'b0, 64'b0);
        check_read(64'h3000300030003000, 1'b0, 5'd3,
                   "independent_row_102");

        // One idle cycle proves pulse outputs return to zero.
        @(posedge clk_i);
        #1;
        check_events(1'b0, 1'b0, 1'b0, FAULT_NONE, "pulse_clear");

        if (errors == 0) begin
            $display("TEST_PASS");
        end else begin
            $display("TEST_FAIL errors=%0d", errors);
        end
        $finish;
    end

endmodule
