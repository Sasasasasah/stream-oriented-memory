`timescale 1ns/1ps

module tb_mem_bank_control_column;

    reg         clk_i;
    reg         rst_ni;
    reg         south_cmd_valid_i;
    reg  [31:0] south_cmd_i;

    wire        north_cmd_valid_o;
    wire [31:0] north_cmd_o;
    wire [3:0]  leaf_cmd_valid_o;
    wire [11:0] leaf_cmd_opcode_o;
    wire [59:0] leaf_cmd_row_o;
    wire [3:0]  leaf_cmd_stream_dir_o;
    wire [19:0] leaf_cmd_stream_idx_o;
    wire [3:0]  leaf_cmd_preserve_o;
    wire        pipeline_busy_o;

    reg         expected_stage1_valid;
    reg         expected_stage2_valid;
    reg         expected_stage3_valid;
    reg         expected_north_valid;
    reg  [31:0] expected_stage1_cmd;
    reg  [31:0] expected_stage2_cmd;
    reg  [31:0] expected_stage3_cmd;
    reg  [31:0] expected_north_cmd;

    integer errors;

    mem_bank_control_column dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .south_cmd_valid_i(south_cmd_valid_i),
        .south_cmd_i(south_cmd_i),
        .north_cmd_valid_o(north_cmd_valid_o),
        .north_cmd_o(north_cmd_o),
        .leaf_cmd_valid_o(leaf_cmd_valid_o),
        .leaf_cmd_opcode_o(leaf_cmd_opcode_o),
        .leaf_cmd_row_o(leaf_cmd_row_o),
        .leaf_cmd_stream_dir_o(leaf_cmd_stream_dir_o),
        .leaf_cmd_stream_idx_o(leaf_cmd_stream_idx_o),
        .leaf_cmd_preserve_o(leaf_cmd_preserve_o),
        .pipeline_busy_o(pipeline_busy_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [31:0] make_cmd;
        input [2:0]  opcode;
        input [5:0]  stream_selector;
        input [5:0]  map_stream;
        input [14:0] row;
        input        reserved_bit;
        input        preserve;
        begin
            make_cmd = 32'b0;
            make_cmd[2:0]   = opcode;
            make_cmd[8:3]   = stream_selector;
            make_cmd[14:9]  = map_stream;
            make_cmd[29:15] = row;
            make_cmd[30]    = reserved_bit;
            make_cmd[31]    = preserve;
        end
    endfunction

    task clear_expected;
        begin
            expected_stage1_valid = 1'b0;
            expected_stage2_valid = 1'b0;
            expected_stage3_valid = 1'b0;
            expected_north_valid  = 1'b0;
            expected_stage1_cmd   = 32'b0;
            expected_stage2_cmd   = 32'b0;
            expected_stage3_cmd   = 32'b0;
            expected_north_cmd    = 32'b0;
        end
    endtask

    task check_tile;
        input integer tile;
        input         expected_valid;
        input [31:0]  expected_raw;
        input [8*48-1:0] test_name;
        begin
            if (leaf_cmd_valid_o[tile] !== expected_valid) begin
                $display("ERROR %0s tile%0d valid expected=%0d actual=%0d",
                         test_name, tile, expected_valid,
                         leaf_cmd_valid_o[tile]);
                errors = errors + 1;
            end
            if (expected_valid) begin
                if (leaf_cmd_opcode_o[tile*3 +: 3] !== expected_raw[2:0]) begin
                    $display("ERROR %0s tile%0d opcode mismatch", test_name, tile);
                    errors = errors + 1;
                end
                if (leaf_cmd_row_o[tile*15 +: 15] !== expected_raw[29:15]) begin
                    $display("ERROR %0s tile%0d row mismatch", test_name, tile);
                    errors = errors + 1;
                end
                if (leaf_cmd_stream_dir_o[tile] !== expected_raw[8]) begin
                    $display("ERROR %0s tile%0d direction mismatch", test_name, tile);
                    errors = errors + 1;
                end
                if (leaf_cmd_stream_idx_o[tile*5 +: 5] !== expected_raw[7:3]) begin
                    $display("ERROR %0s tile%0d stream index mismatch",
                             test_name, tile);
                    errors = errors + 1;
                end
                if (leaf_cmd_preserve_o[tile] !== expected_raw[31]) begin
                    $display("ERROR %0s tile%0d preserve mismatch", test_name, tile);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task run_cycle;
        input        input_valid;
        input [31:0] input_cmd;
        input [8*48-1:0] test_name;
        reg expected_busy;
        begin
            @(negedge clk_i);
            south_cmd_valid_i = input_valid;
            south_cmd_i       = input_cmd;
            #1;

            check_tile(0, input_valid, input_cmd, test_name);
            check_tile(1, expected_stage1_valid, expected_stage1_cmd, test_name);
            check_tile(2, expected_stage2_valid, expected_stage2_cmd, test_name);
            check_tile(3, expected_stage3_valid, expected_stage3_cmd, test_name);

            expected_busy = input_valid | expected_stage1_valid |
                            expected_stage2_valid | expected_stage3_valid;
            if (pipeline_busy_o !== expected_busy) begin
                $display("ERROR %0s busy expected=%0d actual=%0d",
                         test_name, expected_busy, pipeline_busy_o);
                errors = errors + 1;
            end
            if (north_cmd_valid_o !== expected_north_valid) begin
                $display("ERROR %0s north valid expected=%0d actual=%0d",
                         test_name, expected_north_valid, north_cmd_valid_o);
                errors = errors + 1;
            end
            if (expected_north_valid && north_cmd_o !== expected_north_cmd) begin
                $display("ERROR %0s north payload expected=%h actual=%h",
                         test_name, expected_north_cmd, north_cmd_o);
                errors = errors + 1;
            end

            @(posedge clk_i);
            #1;
            expected_north_valid  = expected_stage3_valid;
            expected_north_cmd    = expected_stage3_cmd;
            expected_stage3_valid = expected_stage2_valid;
            expected_stage3_cmd   = expected_stage2_cmd;
            expected_stage2_valid = expected_stage1_valid;
            expected_stage2_cmd   = expected_stage1_cmd;
            expected_stage1_valid = input_valid;
            expected_stage1_cmd   = input_cmd;
        end
    endtask

    task reset_pipeline;
        begin
            south_cmd_valid_i = 1'b0;
            south_cmd_i       = 32'b0;
            rst_ni            = 1'b1;
            #2;
            rst_ni = 1'b0;
            #1;
            if (leaf_cmd_valid_o !== 4'b0000 ||
                pipeline_busy_o !== 1'b0 || north_cmd_valid_o !== 1'b0) begin
                $display("ERROR reset_empty_pipeline outputs not clear");
                errors = errors + 1;
            end
            clear_expected();
            @(negedge clk_i);
            rst_ni = 1'b1;
            @(posedge clk_i);
            #1;
        end
    endtask

    reg [31:0] cmd_a;
    reg [31:0] cmd_b;
    reg [31:0] cmd_c;
    reg [31:0] cmd_d;
    reg [31:0] raw_illegal;

    initial begin
        errors = 0;
        south_cmd_valid_i = 1'b0;
        south_cmd_i = 32'b0;
        rst_ni = 1'b1;
        clear_expected();

        cmd_a = make_cmd(3'b000, 6'd3,  6'd0, 15'd10, 1'b0, 1'b0);
        cmd_b = make_cmd(3'b001, 6'd37, 6'd0, 15'd20, 1'b0, 1'b0);
        cmd_c = make_cmd(3'b001, 6'd12, 6'd0, 15'd30, 1'b0, 1'b1);
        cmd_d = make_cmd(3'b000, 6'd63, 6'd0, 15'd40, 1'b0, 1'b0);
        raw_illegal = make_cmd(3'b101, 6'd42, 6'h2D, 15'd1234, 1'b1, 1'b1);

        $display("RUN_TEST reset_empty_pipeline");
        reset_pipeline();

        $display("RUN_TEST single_command_c_to_c_plus_3");
        run_cycle(1'b1, cmd_a, "single_c");
        run_cycle(1'b0, 32'h11111111, "single_c_plus_1");
        run_cycle(1'b0, 32'h22222222, "single_c_plus_2");
        run_cycle(1'b0, 32'h33333333, "single_c_plus_3");
        run_cycle(1'b0, 32'h44444444, "single_north");
        run_cycle(1'b0, 32'h55555555, "single_drained");

        $display("RUN_TEST continuous_a_b_c_d");
        reset_pipeline();
        run_cycle(1'b1, cmd_a, "continuous_a");
        run_cycle(1'b1, cmd_b, "continuous_b");
        run_cycle(1'b1, cmd_c, "continuous_c");
        run_cycle(1'b1, cmd_d, "continuous_d");
        run_cycle(1'b0, 32'b0, "continuous_drain_1");
        run_cycle(1'b0, 32'b0, "continuous_drain_2");
        run_cycle(1'b0, 32'b0, "continuous_drain_3");
        run_cycle(1'b0, 32'b0, "continuous_drain_4");
        run_cycle(1'b0, 32'b0, "continuous_empty");

        $display("RUN_TEST bubble_preservation");
        reset_pipeline();
        run_cycle(1'b1, cmd_a, "bubble_a");
        run_cycle(1'b0, 32'hDEADBEEF, "bubble_gap");
        run_cycle(1'b1, cmd_b, "bubble_b");
        run_cycle(1'b0, 32'b0, "bubble_drain_1");
        run_cycle(1'b0, 32'b0, "bubble_drain_2");
        run_cycle(1'b0, 32'b0, "bubble_drain_3");
        run_cycle(1'b0, 32'b0, "bubble_drain_4");
        run_cycle(1'b0, 32'b0, "bubble_empty");

        $display("RUN_TEST raw_payload_and_decode_preservation");
        reset_pipeline();
        run_cycle(1'b1, raw_illegal, "raw_tile0");
        run_cycle(1'b0, 32'b0, "raw_tile1");
        run_cycle(1'b0, 32'b0, "raw_tile2");
        run_cycle(1'b0, 32'b0, "raw_tile3");
        run_cycle(1'b0, 32'b0, "raw_north");
        run_cycle(1'b0, 32'b0, "raw_empty");

        $display("RUN_TEST pipeline_busy_fill_drain");
        reset_pipeline();
        run_cycle(1'b1, cmd_a, "busy_fill");
        run_cycle(1'b0, 32'b0, "busy_drain_1");
        run_cycle(1'b0, 32'b0, "busy_drain_2");
        run_cycle(1'b0, 32'b0, "busy_drain_3");
        run_cycle(1'b0, 32'b0, "busy_empty");

        if (errors == 0) begin
            $display("TEST_PASS");
        end else begin
            $display("TEST_FAIL errors=%0d", errors);
        end
        $finish;
    end

endmodule
