`timescale 1ns/1ps

module tb_mem_logical_bank;

    localparam [2:0] OPCODE_READ  = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;

    reg          clk_i;
    reg          rst_ni;
    reg          south_cmd_valid_i;
    reg  [31:0]  south_cmd_i;
    reg  [3:0]   stream_valid_i;
    reg  [255:0] stream_data_i;

    wire [3:0]   stream_consume_o;
    wire [3:0]   read_valid_o;
    wire [255:0] read_data_o;
    wire [3:0]   read_stream_dir_o;
    wire [19:0]  read_stream_idx_o;
    wire [3:0]   fault_valid_o;
    wire [7:0]   fault_code_o;
    wire         north_cmd_valid_o;
    wire [31:0]  north_cmd_o;
    wire         pipeline_busy_o;

    integer errors;
    integer tile;

    mem_logical_bank_column dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .south_cmd_valid_i(south_cmd_valid_i),
        .south_cmd_i(south_cmd_i),
        .stream_valid_i(stream_valid_i),
        .stream_data_i(stream_data_i),
        .stream_consume_o(stream_consume_o),
        .read_valid_o(read_valid_o),
        .read_data_o(read_data_o),
        .read_stream_dir_o(read_stream_dir_o),
        .read_stream_idx_o(read_stream_idx_o),
        .fault_valid_o(fault_valid_o),
        .fault_code_o(fault_code_o),
        .north_cmd_valid_o(north_cmd_valid_o),
        .north_cmd_o(north_cmd_o),
        .pipeline_busy_o(pipeline_busy_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [31:0] make_cmd;
        input [2:0]  opcode;
        input [5:0]  stream_selector;
        input [14:0] row;
        input        preserve;
        begin
            make_cmd = 32'b0;
            make_cmd[2:0]   = opcode;
            make_cmd[8:3]   = stream_selector;
            make_cmd[29:15] = row;
            make_cmd[31]    = preserve;
        end
    endfunction

    function [255:0] pack_segments;
        input [63:0] segment0;
        input [63:0] segment1;
        input [63:0] segment2;
        input [63:0] segment3;
        begin
            pack_segments = {segment3, segment2, segment1, segment0};
        end
    endfunction

    task apply_cycle;
        input         command_valid;
        input [31:0]  command;
        input [3:0]   valid_segments;
        input [255:0] data_segments;
        begin
            @(negedge clk_i);
            south_cmd_valid_i = command_valid;
            south_cmd_i       = command;
            stream_valid_i    = valid_segments;
            stream_data_i     = data_segments;
            @(posedge clk_i);
            #1;
            south_cmd_valid_i = 1'b0;
            south_cmd_i       = 32'b0;
            stream_valid_i    = 4'b0;
            stream_data_i     = 256'b0;
        end
    endtask

    task check_masks;
        input [3:0] expected_consume;
        input [3:0] expected_read;
        input [3:0] expected_fault;
        input [8*56-1:0] test_name;
        begin
            if (stream_consume_o !== expected_consume) begin
                $display("ERROR %0s consume expected=%b actual=%b",
                         test_name, expected_consume, stream_consume_o);
                errors = errors + 1;
            end
            if (read_valid_o !== expected_read) begin
                $display("ERROR %0s read expected=%b actual=%b",
                         test_name, expected_read, read_valid_o);
                errors = errors + 1;
            end
            if (fault_valid_o !== expected_fault) begin
                $display("ERROR %0s fault expected=%b actual=%b",
                         test_name, expected_fault, fault_valid_o);
                errors = errors + 1;
            end
        end
    endtask

    task check_read_tile;
        input integer tile_index;
        input [63:0] expected_data;
        input        expected_direction;
        input [4:0]  expected_stream_index;
        input [8*56-1:0] test_name;
        begin
            if (read_data_o[tile_index*64 +: 64] !== expected_data) begin
                $display("ERROR %0s tile%0d data expected=%h actual=%h",
                         test_name, tile_index, expected_data,
                         read_data_o[tile_index*64 +: 64]);
                errors = errors + 1;
            end
            if (read_stream_dir_o[tile_index] !== expected_direction) begin
                $display("ERROR %0s tile%0d direction mismatch",
                         test_name, tile_index);
                errors = errors + 1;
            end
            if (read_stream_idx_o[tile_index*5 +: 5] !==
                expected_stream_index) begin
                $display("ERROR %0s tile%0d stream index mismatch",
                         test_name, tile_index);
                errors = errors + 1;
            end
        end
    endtask

    task issue_write_wave;
        input [14:0]  row;
        input         preserve;
        input [3:0]   valid_segments;
        input [255:0] data_segments;
        input [8*56-1:0] test_name;
        reg [31:0] command;
        reg [3:0] expected_consume;
        reg [3:0] expected_fault;
        integer index;
        begin
            command = make_cmd(OPCODE_WRITE, 6'd5, row, preserve);
            for (index = 0; index < 4; index = index + 1) begin
                apply_cycle(index == 0, command, valid_segments, data_segments);
                expected_consume = 4'b0;
                expected_fault   = 4'b0;
                if (!preserve && valid_segments[index]) begin
                    expected_consume[index] = 1'b1;
                end
                if (!preserve && !valid_segments[index]) begin
                    expected_fault[index] = 1'b1;
                end
                check_masks(expected_consume, 4'b0, expected_fault, test_name);
            end
        end
    endtask

    task issue_read_wave;
        input [14:0]  row;
        input         direction;
        input [4:0]   stream_index;
        input [255:0] expected_data;
        input [8*56-1:0] test_name;
        reg [31:0] command;
        reg [3:0] expected_read_mask;
        integer index;
        begin
            command = make_cmd(OPCODE_READ,
                               {direction, stream_index}, row, 1'b0);
            for (index = 0; index < 4; index = index + 1) begin
                apply_cycle(index == 0, command, 4'b0, 256'b0);
                expected_read_mask = 4'b0001 << index;
                check_masks(4'b0, expected_read_mask, 4'b0, test_name);
                check_read_tile(index, expected_data[index*64 +: 64],
                                direction, stream_index, test_name);
            end
        end
    endtask

    task reset_dut;
        begin
            south_cmd_valid_i = 1'b0;
            south_cmd_i       = 32'b0;
            stream_valid_i    = 4'b0;
            stream_data_i     = 256'b0;
            rst_ni            = 1'b1;
            #2;
            rst_ni = 1'b0;
            #1;
            if (stream_consume_o !== 4'b0 || read_valid_o !== 4'b0 ||
                fault_valid_o !== 4'b0 || pipeline_busy_o !== 1'b0 ||
                north_cmd_valid_o !== 1'b0) begin
                $display("ERROR reset outputs not clear");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            @(posedge clk_i);
            #1;
        end
    endtask

    reg [255:0] data_a;
    reg [255:0] data_b;
    reg [255:0] data_c;
    reg [255:0] data_d;
    reg [255:0] old_data;
    reg [255:0] new_data;
    reg [31:0]  cmd_a;
    reg [31:0]  cmd_b;
    reg [31:0]  cmd_c;
    reg [31:0]  cmd_d;

    initial begin
        errors = 0;
        rst_ni = 1'b1;
        south_cmd_valid_i = 1'b0;
        south_cmd_i = 32'b0;
        stream_valid_i = 4'b0;
        stream_data_i = 256'b0;

        data_a = pack_segments(64'hA000000000000000,
                               64'hA100000000000001,
                               64'hA200000000000002,
                               64'hA300000000000003);
        data_b = pack_segments(64'hB000000000000000,
                               64'hB100000000000001,
                               64'hB200000000000002,
                               64'hB300000000000003);
        data_c = pack_segments(64'hC000000000000000,
                               64'hC100000000000001,
                               64'hC200000000000002,
                               64'hC300000000000003);
        data_d = pack_segments(64'hD000000000000000,
                               64'hD100000000000001,
                               64'hD200000000000002,
                               64'hD300000000000003);

        $display("RUN_TEST reset");
        reset_dut();

        $display("RUN_TEST single_read_wave");
        issue_write_wave(15'd10, 1'b0, 4'b1111, data_a,
                         "single_read_setup");
        issue_read_wave(15'd10, 1'b0, 5'd7, data_a,
                        "single_read_wave");

        $display("RUN_TEST single_write_wave");
        issue_write_wave(15'd20, 1'b0, 4'b1111, data_b,
                         "single_write_wave");
        issue_read_wave(15'd20, 1'b1, 5'd9, data_b,
                        "single_write_readback");

        $display("RUN_TEST write_consume");
        issue_write_wave(15'd21, 1'b0, 4'b1111, data_c,
                         "write_consume");

        $display("RUN_TEST writetap");
        issue_write_wave(15'd30, 1'b1, 4'b1111, data_d, "writetap");
        issue_read_wave(15'd30, 1'b0, 5'd11, data_d,
                        "writetap_readback");

        $display("RUN_TEST writetap_sparse_valid");
        old_data = pack_segments(64'h4000000000000000,
                                 64'h4100000000000001,
                                 64'h4200000000000002,
                                 64'h4300000000000003);
        new_data = pack_segments(64'h5000000000000000,
                                 64'h5100000000000001,
                                 64'h5200000000000002,
                                 64'h5300000000000003);
        issue_write_wave(15'd40, 1'b0, 4'b1111, old_data,
                         "sparse_setup");
        issue_write_wave(15'd40, 1'b1, 4'b0101, new_data,
                         "writetap_sparse");
        issue_read_wave(15'd40, 1'b0, 5'd12,
                        pack_segments(64'h5000000000000000,
                                      64'h4100000000000001,
                                      64'h5200000000000002,
                                      64'h4300000000000003),
                        "writetap_sparse_readback");

        $display("RUN_TEST normal_write_invalid_tile");
        old_data = pack_segments(64'h6000000000000000,
                                 64'h6100000000000001,
                                 64'h6200000000000002,
                                 64'h6300000000000003);
        new_data = pack_segments(64'h7000000000000000,
                                 64'h7100000000000001,
                                 64'h7200000000000002,
                                 64'h7300000000000003);
        issue_write_wave(15'd50, 1'b0, 4'b1111, old_data,
                         "invalid_tile_setup");
        issue_write_wave(15'd50, 1'b0, 4'b1011, new_data,
                         "normal_write_invalid_tile");
        issue_read_wave(15'd50, 1'b1, 5'd13,
                        pack_segments(64'h7000000000000000,
                                      64'h7100000000000001,
                                      64'h6200000000000002,
                                      64'h7300000000000003),
                        "invalid_tile_readback");

        $display("RUN_TEST continuous_command_waves");
        cmd_a = make_cmd(OPCODE_WRITE, 6'd1, 15'd60, 1'b0);
        cmd_b = make_cmd(OPCODE_WRITE, 6'd2, 15'd61, 1'b0);
        cmd_c = make_cmd(OPCODE_WRITE, 6'd33, 15'd62, 1'b0);
        cmd_d = make_cmd(OPCODE_WRITE, 6'd63, 15'd63, 1'b0);
        apply_cycle(1'b1, cmd_a, 4'b1111,
                    pack_segments(data_a[63:0], 64'b0, 64'b0, 64'b0));
        check_masks(4'b0001, 4'b0, 4'b0, "continuous_cycle_0");
        apply_cycle(1'b1, cmd_b, 4'b1111,
                    pack_segments(data_b[63:0], data_a[127:64],
                                  64'b0, 64'b0));
        check_masks(4'b0011, 4'b0, 4'b0, "continuous_cycle_1");
        apply_cycle(1'b1, cmd_c, 4'b1111,
                    pack_segments(data_c[63:0], data_b[127:64],
                                  data_a[191:128], 64'b0));
        check_masks(4'b0111, 4'b0, 4'b0, "continuous_cycle_2");
        apply_cycle(1'b1, cmd_d, 4'b1111,
                    pack_segments(data_d[63:0], data_c[127:64],
                                  data_b[191:128], data_a[255:192]));
        check_masks(4'b1111, 4'b0, 4'b0, "continuous_cycle_3");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, data_d[127:64],
                                  data_c[191:128], data_b[255:192]));
        check_masks(4'b1110, 4'b0, 4'b0, "continuous_cycle_4");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, 64'b0,
                                  data_d[191:128], data_c[255:192]));
        check_masks(4'b1100, 4'b0, 4'b0, "continuous_cycle_5");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, 64'b0, 64'b0,
                                  data_d[255:192]));
        check_masks(4'b1000, 4'b0, 4'b0, "continuous_cycle_6");
        issue_read_wave(15'd60, 1'b0, 5'd1, data_a, "continuous_row_a");
        issue_read_wave(15'd61, 1'b0, 5'd2, data_b, "continuous_row_b");
        issue_read_wave(15'd62, 1'b1, 5'd1, data_c, "continuous_row_c");
        issue_read_wave(15'd63, 1'b1, 5'd31, data_d, "continuous_row_d");

        $display("RUN_TEST bubble_preservation");
        cmd_a = make_cmd(OPCODE_WRITE, 6'd4, 15'd70, 1'b0);
        cmd_b = make_cmd(OPCODE_WRITE, 6'd5, 15'd71, 1'b0);
        apply_cycle(1'b1, cmd_a, 4'b1111,
                    pack_segments(data_a[63:0], 64'b0, 64'b0, 64'b0));
        check_masks(4'b0001, 4'b0, 4'b0, "bubble_cycle_0");
        apply_cycle(1'b0, 32'hDEADBEEF, 4'b1111,
                    pack_segments(64'b0, data_a[127:64], 64'b0, 64'b0));
        check_masks(4'b0010, 4'b0, 4'b0, "bubble_cycle_1");
        apply_cycle(1'b1, cmd_b, 4'b1111,
                    pack_segments(data_b[63:0], 64'b0,
                                  data_a[191:128], 64'b0));
        check_masks(4'b0101, 4'b0, 4'b0, "bubble_cycle_2");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, data_b[127:64], 64'b0,
                                  data_a[255:192]));
        check_masks(4'b1010, 4'b0, 4'b0, "bubble_cycle_3");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, 64'b0, data_b[191:128], 64'b0));
        check_masks(4'b0100, 4'b0, 4'b0, "bubble_cycle_4");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, 64'b0, 64'b0, data_b[255:192]));
        check_masks(4'b1000, 4'b0, 4'b0, "bubble_cycle_5");

        $display("RUN_TEST integration_raw");
        cmd_a = make_cmd(OPCODE_WRITE, 6'd6, 15'd80, 1'b0);
        cmd_b = make_cmd(OPCODE_READ, {1'b1, 5'd23}, 15'd80, 1'b0);
        apply_cycle(1'b1, cmd_a, 4'b1111,
                    pack_segments(data_c[63:0], 64'b0, 64'b0, 64'b0));
        check_masks(4'b0001, 4'b0, 4'b0, "raw_cycle_0");
        apply_cycle(1'b1, cmd_b, 4'b1111,
                    pack_segments(64'b0, data_c[127:64], 64'b0, 64'b0));
        check_masks(4'b0010, 4'b0001, 4'b0, "raw_cycle_1");
        check_read_tile(0, data_c[63:0], 1'b1, 5'd23, "raw_tile0");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, 64'b0, data_c[191:128], 64'b0));
        check_masks(4'b0100, 4'b0010, 4'b0, "raw_cycle_2");
        check_read_tile(1, data_c[127:64], 1'b1, 5'd23, "raw_tile1");
        apply_cycle(1'b0, 32'b0, 4'b1111,
                    pack_segments(64'b0, 64'b0, 64'b0, data_c[255:192]));
        check_masks(4'b1000, 4'b0100, 4'b0, "raw_cycle_3");
        check_read_tile(2, data_c[191:128], 1'b1, 5'd23, "raw_tile2");
        apply_cycle(1'b0, 32'b0, 4'b0, 256'b0);
        check_masks(4'b0000, 4'b1000, 4'b0, "raw_cycle_4");
        check_read_tile(3, data_c[255:192], 1'b1, 5'd23, "raw_tile3");

        $display("RUN_TEST capacity_and_row_independence");
        issue_write_wave(15'd0, 1'b0, 4'b1111, data_a, "capacity_row_0");
        issue_write_wave(15'd16384, 1'b0, 4'b1111, data_b,
                         "capacity_row_mid");
        issue_write_wave(15'd32767, 1'b0, 4'b1111, data_d,
                         "capacity_row_max");
        issue_read_wave(15'd0, 1'b0, 5'd2, data_a, "capacity_read_0");
        issue_read_wave(15'd16384, 1'b1, 5'd18, data_b,
                        "capacity_read_mid");
        issue_read_wave(15'd32767, 1'b1, 5'd31, data_d,
                        "capacity_read_max");

        $display("RUN_TEST read_metadata");
        issue_read_wave(15'd20, 1'b1, 5'd29, data_b, "read_metadata");

        $display("RUN_TEST reset_control_outputs");
        apply_cycle(1'b1, make_cmd(OPCODE_READ, 6'd1, 15'd20, 1'b0),
                    4'b0, 256'b0);
        rst_ni = 1'b0;
        #1;
        if (stream_consume_o !== 4'b0 || read_valid_o !== 4'b0 ||
            fault_valid_o !== 4'b0 || pipeline_busy_o !== 1'b0 ||
            north_cmd_valid_o !== 1'b0) begin
            $display("ERROR reset_control_outputs not clear");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TEST_PASS");
        end else begin
            $display("TEST_FAIL errors=%0d", errors);
        end
        $finish;
    end

endmodule
