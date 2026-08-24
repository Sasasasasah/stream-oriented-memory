`timescale 1ns/1ps

module tb_mem_slice;

    localparam [2:0] OPCODE_READ  = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;
    localparam [2:0] FAULT_ISSUE = 3'd1;
    localparam [2:0] FAULT_LEAF = 3'd2;
    localparam [2:0] FAULT_COLLISION = 3'd3;

    reg          clk_i;
    reg          rst_ni;
    reg  [1:0]   bank_issue_valid_i;
    reg  [63:0]  bank_issue_i;
    reg  [255:0] sr_state_valid_i;
    reg  [16383:0] sr_state_data_i;
    reg  [7:0]   producer_collision_i;

    wire [511:0] sr_consume_o;
    wire [7:0]   sr_inject_valid_o;
    wire [511:0] sr_inject_data_o;
    wire [7:0]   sr_inject_stream_dir_o;
    wire [39:0]  sr_inject_stream_idx_o;
    wire [1:0]   mem_fault_valid_o;
    wire [5:0]   mem_fault_code_o;
    wire [1:0]   mem_fault_bank_id_o;
    wire [1:0]   mem_fault_tile_valid_o;
    wire [3:0]   mem_fault_tile_id_o;
    wire [29:0]  mem_fault_row_o;
    wire [1:0]   bank_north_cmd_valid_o;
    wire [63:0]  bank_north_cmd_o;
    wire [1:0]   bank_pipeline_busy_o;
    wire         slice_busy_o;

    integer errors;
    integer index;

    mem_slice dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .bank_issue_valid_i(bank_issue_valid_i),
        .bank_issue_i(bank_issue_i),
        .sr_state_valid_i(sr_state_valid_i),
        .sr_state_data_i(sr_state_data_i),
        .producer_collision_i(producer_collision_i),
        .sr_consume_o(sr_consume_o),
        .sr_inject_valid_o(sr_inject_valid_o),
        .sr_inject_data_o(sr_inject_data_o),
        .sr_inject_stream_dir_o(sr_inject_stream_dir_o),
        .sr_inject_stream_idx_o(sr_inject_stream_idx_o),
        .mem_fault_valid_o(mem_fault_valid_o),
        .mem_fault_code_o(mem_fault_code_o),
        .mem_fault_bank_id_o(mem_fault_bank_id_o),
        .mem_fault_tile_valid_o(mem_fault_tile_valid_o),
        .mem_fault_tile_id_o(mem_fault_tile_id_o),
        .mem_fault_row_o(mem_fault_row_o),
        .bank_north_cmd_valid_o(bank_north_cmd_valid_o),
        .bank_north_cmd_o(bank_north_cmd_o),
        .bank_pipeline_busy_o(bank_pipeline_busy_o),
        .slice_busy_o(slice_busy_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [31:0] make_cmd;
        input [2:0]  opcode;
        input        direction;
        input [4:0]  stream_index;
        input [5:0]  map_stream;
        input [14:0] row;
        input        reserved_bit;
        input        preserve;
        begin
            make_cmd = 32'b0;
            make_cmd[2:0]   = opcode;
            make_cmd[8:3]   = {direction, stream_index};
            make_cmd[14:9]  = map_stream;
            make_cmd[29:15] = row;
            make_cmd[30]    = reserved_bit;
            make_cmd[31]    = preserve;
        end
    endfunction

    function integer sr_cell;
        input       direction;
        input [4:0] stream_index;
        input integer tile;
        begin
            sr_cell = (direction ? 128 : 0) + stream_index*4 + tile;
        end
    endfunction

    function integer consume_cell;
        input integer bank;
        input         direction;
        input [4:0]   stream_index;
        input integer tile;
        begin
            consume_cell = bank*256 + sr_cell(direction, stream_index, tile);
        end
    endfunction

    function integer injection_entry;
        input integer bank;
        input integer tile;
        begin
            injection_entry = bank*4 + tile;
        end
    endfunction

    function integer count_consume;
        integer bit_index;
        begin
            count_consume = 0;
            for (bit_index = 0; bit_index < 512; bit_index = bit_index + 1)
                count_consume = count_consume + sr_consume_o[bit_index];
        end
    endfunction

    function integer count_inject;
        integer bit_index;
        begin
            count_inject = 0;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                count_inject = count_inject + sr_inject_valid_o[bit_index];
        end
    endfunction

    function [255:0] pack_segments;
        input [63:0] d0;
        input [63:0] d1;
        input [63:0] d2;
        input [63:0] d3;
        begin
            pack_segments = {d3, d2, d1, d0};
        end
    endfunction

    task clear_sr_state;
        begin
            sr_state_valid_i = 256'b0;
            sr_state_data_i  = 16384'b0;
        end
    endtask

    task set_sr_selector;
        input         direction;
        input [4:0]   stream_index;
        input [3:0]   valid_mask;
        input [255:0] segments;
        integer tile;
        integer cell_index;
        begin
            for (tile = 0; tile < 4; tile = tile + 1) begin
                cell_index = sr_cell(direction, stream_index, tile);
                sr_state_valid_i[cell_index] = valid_mask[tile];
                sr_state_data_i[cell_index*64 +: 64] = segments[tile*64 +: 64];
            end
        end
    endtask

    task apply_cycle;
        input [1:0]  valid_mask;
        input [31:0] bank0_command;
        input [31:0] bank1_command;
        begin
            @(negedge clk_i);
            bank_issue_valid_i = valid_mask;
            bank_issue_i[31:0] = bank0_command;
            bank_issue_i[63:32] = bank1_command;
            @(posedge clk_i);
            #1;
        end
    endtask

    task idle_cycle;
        begin
            apply_cycle(2'b00, 32'b0, 32'b0);
        end
    endtask

    task reset_dut;
        begin
            bank_issue_valid_i = 2'b0;
            bank_issue_i = 64'b0;
            producer_collision_i = 8'b0;
            clear_sr_state();
            rst_ni = 1'b0;
            #1;
            if (bank_pipeline_busy_o !== 2'b0 || slice_busy_o !== 1'b0 ||
                sr_inject_valid_o !== 8'b0 || sr_consume_o !== 512'b0 ||
                mem_fault_valid_o !== 2'b0) begin
                $display("ERROR reset outputs not idle");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            @(posedge clk_i);
            #1;
        end
    endtask

    task setup_write;
        input integer bank;
        input [14:0] row;
        input         direction;
        input [4:0]   stream_index;
        input [255:0] segments;
        reg [31:0] command;
        integer cycle;
        begin
            set_sr_selector(direction, stream_index, 4'b1111, segments);
            command = make_cmd(OPCODE_WRITE, direction, stream_index,
                               6'b0, row, 1'b0, 1'b0);
            for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
                if (bank == 0)
                    apply_cycle(cycle == 0 ? 2'b01 : 2'b00,
                                command, 32'b0);
                else
                    apply_cycle(cycle == 0 ? 2'b10 : 2'b00,
                                32'b0, command);
            end
        end
    endtask

    task check_injection;
        input integer bank;
        input integer tile;
        input [63:0] expected_data;
        input        expected_direction;
        input [4:0]  expected_stream;
        input [8*48-1:0] test_name;
        integer entry;
        begin
            entry = injection_entry(bank, tile);
            if (!sr_inject_valid_o[entry] ||
                sr_inject_data_o[entry*64 +: 64] !== expected_data ||
                sr_inject_stream_dir_o[entry] !== expected_direction ||
                sr_inject_stream_idx_o[entry*5 +: 5] !== expected_stream) begin
                $display("ERROR %0s bank%0d tile%0d injection mismatch",
                         test_name, bank, tile);
                errors = errors + 1;
            end
        end
    endtask

    task check_bank_readback;
        input integer bank;
        input [14:0] row;
        input        direction;
        input [4:0]  stream_index;
        input [255:0] expected_segments;
        input [8*48-1:0] test_name;
        reg [31:0] command;
        integer tile;
        begin
            command = make_cmd(OPCODE_READ, direction, stream_index,
                               6'b0, row, 1'b0, 1'b0);
            for (tile = 0; tile < 4; tile = tile + 1) begin
                if (bank == 0)
                    apply_cycle(tile == 0 ? 2'b01 : 2'b00,
                                command, 32'b0);
                else
                    apply_cycle(tile == 0 ? 2'b10 : 2'b00,
                                32'b0, command);
                if (count_inject() != 1) begin
                    $display("ERROR %0s unexpected injection count", test_name);
                    errors = errors + 1;
                end
                check_injection(bank, tile,
                                expected_segments[tile*64 +: 64],
                                direction, stream_index, test_name);
            end
        end
    endtask

    task check_illegal_issue;
        input [31:0] command;
        input [8*48-1:0] test_name;
        begin
            apply_cycle(2'b01, command, 32'b0);
            if (mem_fault_valid_o !== 2'b01 ||
                mem_fault_code_o[2:0] !== FAULT_ISSUE ||
                bank_pipeline_busy_o[0] !== 1'b0 ||
                sr_consume_o !== 512'b0 || sr_inject_valid_o !== 8'b0) begin
                $display("ERROR %0s illegal issue handling mismatch", test_name);
                errors = errors + 1;
            end
            idle_cycle();
            if (mem_fault_valid_o !== 2'b0 || bank_pipeline_busy_o !== 2'b0) begin
                $display("ERROR %0s illegal issue did not clear", test_name);
                errors = errors + 1;
            end
        end
    endtask

    reg [255:0] data_a;
    reg [255:0] data_b;
    reg [255:0] data_c;
    reg [255:0] data_d;
    reg [31:0] cmd0;
    reg [31:0] cmd1;
    reg [31:0] command_a [0:3];
    reg [31:0] command_b [0:3];
    integer cycle;
    integer tile;
    integer cell0;
    integer cell1;

    initial begin
        errors = 0;
        rst_ni = 1'b1;
        bank_issue_valid_i = 2'b0;
        bank_issue_i = 64'b0;
        producer_collision_i = 8'b0;
        clear_sr_state();

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

        $display("RUN_TEST bank_independence");
        reset_dut();
        setup_write(0, 15'd100, 1'b0, 5'd1, data_a);
        clear_sr_state();
        set_sr_selector(1'b1, 5'd2, 4'b1111, data_b);
        cmd0 = make_cmd(OPCODE_READ, 1'b0, 5'd10,
                        6'b0, 15'd100, 1'b0, 1'b0);
        cmd1 = make_cmd(OPCODE_WRITE, 1'b1, 5'd2,
                        6'b0, 15'd101, 1'b0, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? 2'b11 : 2'b00, cmd0, cmd1);
            check_injection(0, tile, data_a[tile*64 +: 64],
                            1'b0, 5'd10, "bank_independence");
            cell1 = consume_cell(1, 1'b1, 5'd2, tile);
            if (!sr_consume_o[cell1] || count_consume() != 1 ||
                bank_pipeline_busy_o !== (tile == 3 ? 2'b00 : 2'b11)) begin
                $display("ERROR bank_independence tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST dual_bank_simultaneous_write");
        reset_dut();
        set_sr_selector(1'b0, 5'd3, 4'b1111, data_a);
        set_sr_selector(1'b1, 5'd4, 4'b1111, data_b);
        cmd0 = make_cmd(OPCODE_WRITE, 1'b0, 5'd3,
                        6'b0, 15'd110, 1'b0, 1'b0);
        cmd1 = make_cmd(OPCODE_WRITE, 1'b1, 5'd4,
                        6'b0, 15'd111, 1'b0, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? 2'b11 : 2'b00, cmd0, cmd1);
            cell0 = consume_cell(0, 1'b0, 5'd3, tile);
            cell1 = consume_cell(1, 1'b1, 5'd4, tile);
            if (!sr_consume_o[cell0] || !sr_consume_o[cell1] ||
                count_consume() != 2) begin
                $display("ERROR dual write consume tile%0d", tile);
                errors = errors + 1;
            end
        end
        check_bank_readback(0, 15'd110, 1'b0, 5'd3,
                            data_a, "dual_write_bank0");
        check_bank_readback(1, 15'd111, 1'b1, 5'd4,
                            data_b, "dual_write_bank1");

        $display("RUN_TEST same_stream_broadcast_write");
        reset_dut();
        set_sr_selector(1'b0, 5'd5, 4'b1111, data_c);
        cmd0 = make_cmd(OPCODE_WRITE, 1'b0, 5'd5,
                        6'b0, 15'd120, 1'b0, 1'b0);
        cmd1 = make_cmd(OPCODE_WRITE, 1'b0, 5'd5,
                        6'b0, 15'd121, 1'b0, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? 2'b11 : 2'b00, cmd0, cmd1);
            cell0 = consume_cell(0, 1'b0, 5'd5, tile);
            cell1 = consume_cell(1, 1'b0, 5'd5, tile);
            if (!sr_consume_o[cell0] || !sr_consume_o[cell1] ||
                count_consume() != 2) begin
                $display("ERROR broadcast consume tile%0d", tile);
                errors = errors + 1;
            end
        end
        check_bank_readback(0, 15'd120, 1'b0, 5'd20,
                            data_c, "broadcast_bank0");
        check_bank_readback(1, 15'd121, 1'b1, 5'd21,
                            data_c, "broadcast_bank1");

        $display("RUN_TEST read_write_parallel");
        reset_dut();
        set_sr_selector(1'b0, 5'd7, 4'b1111, data_d);
        cmd0 = make_cmd(OPCODE_READ, 1'b1, 5'd6,
                        6'b0, 15'd110, 1'b0, 1'b0);
        cmd1 = make_cmd(OPCODE_WRITE, 1'b0, 5'd7,
                        6'b0, 15'd130, 1'b0, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? 2'b11 : 2'b00, cmd0, cmd1);
            check_injection(0, tile, data_a[tile*64 +: 64],
                            1'b1, 5'd6, "read_write_parallel");
            cell1 = consume_cell(1, 1'b0, 5'd7, tile);
            if (!sr_consume_o[cell1] || count_consume() != 1) begin
                $display("ERROR read/write parallel tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST dual_read_different_destination");
        reset_dut();
        cmd0 = make_cmd(OPCODE_READ, 1'b0, 5'd8,
                        6'b0, 15'd110, 1'b0, 1'b0);
        cmd1 = make_cmd(OPCODE_READ, 1'b1, 5'd9,
                        6'b0, 15'd111, 1'b0, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? 2'b11 : 2'b00, cmd0, cmd1);
            if (count_inject() != 2) begin
                $display("ERROR dual read count tile%0d", tile);
                errors = errors + 1;
            end
            check_injection(0, tile, data_a[tile*64 +: 64],
                            1'b0, 5'd8, "dual_read_bank0");
            check_injection(1, tile, data_b[tile*64 +: 64],
                            1'b1, 5'd9, "dual_read_bank1");
        end

        $display("RUN_TEST producer_collision_feedback");
        reset_dut();
        setup_write(0, 15'd150, 1'b0, 5'd11, data_d);
        cmd0 = make_cmd(OPCODE_READ, 1'b1, 5'd12,
                        6'b0, 15'd150, 1'b0, 1'b0);
        producer_collision_i[3:0] = 4'b1111;
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? 2'b01 : 2'b00, cmd0, 32'b0);
            check_injection(0, tile, data_d[tile*64 +: 64],
                            1'b1, 5'd12, "collision_injection");
            if (!mem_fault_valid_o[0] ||
                mem_fault_code_o[2:0] !== FAULT_COLLISION ||
                !mem_fault_tile_valid_o[0] ||
                mem_fault_tile_id_o[1:0] !== tile[1:0] ||
                mem_fault_row_o[14:0] !== 15'd150) begin
                $display("ERROR collision fault tile%0d", tile);
                errors = errors + 1;
            end
        end
        producer_collision_i = 8'b0;

        $display("RUN_TEST full_payload_legality");
        reset_dut();
        check_illegal_issue(make_cmd(OPCODE_WRITE, 1'b0, 5'd1,
                                     6'b0, 15'd160, 1'b1, 1'b0),
                            "reserved_bit");
        check_illegal_issue(make_cmd(OPCODE_WRITE, 1'b0, 5'd1,
                                     6'd1, 15'd161, 1'b0, 1'b0),
                            "map_stream");
        check_illegal_issue(make_cmd(3'b101, 1'b0, 5'd1,
                                     6'b0, 15'd162, 1'b0, 1'b0),
                            "unsupported_opcode");
        check_illegal_issue(make_cmd(OPCODE_READ, 1'b0, 5'd1,
                                     6'b0, 15'd163, 1'b0, 1'b1),
                            "read_preserve");
        clear_sr_state();
        set_sr_selector(1'b0, 5'd13, 4'b1011, data_a);
        cmd1 = make_cmd(OPCODE_WRITE, 1'b0, 5'd13,
                        6'b0, 15'd164, 1'b0, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? 2'b10 : 2'b00, 32'b0, cmd1);
            if (tile == 2) begin
                if (!mem_fault_valid_o[1] ||
                    mem_fault_code_o[5:3] !== FAULT_LEAF ||
                    mem_fault_tile_id_o[3:2] !== 2'd2) begin
                    $display("ERROR leaf fault aggregation");
                    errors = errors + 1;
                end
            end
        end

        $display("RUN_TEST reset_and_independence");
        reset_dut();
        set_sr_selector(1'b0, 5'd14, 4'b1111, data_a);
        set_sr_selector(1'b1, 5'd15, 4'b1111, data_b);
        cmd0 = make_cmd(OPCODE_WRITE, 1'b0, 5'd14,
                        6'b0, 15'd170, 1'b0, 1'b0);
        cmd1 = make_cmd(OPCODE_WRITE, 1'b1, 5'd15,
                        6'b0, 15'd171, 1'b0, 1'b0);
        apply_cycle(2'b11, cmd0, cmd1);
        rst_ni = 1'b0;
        #1;
        if (bank_pipeline_busy_o !== 2'b0 || slice_busy_o !== 1'b0 ||
            sr_inject_valid_o !== 8'b0 || sr_consume_o !== 512'b0 ||
            mem_fault_valid_o !== 2'b0) begin
            $display("ERROR active reset did not clear transient state");
            errors = errors + 1;
        end
        @(negedge clk_i);
        bank_issue_valid_i = 2'b0;
        rst_ni = 1'b1;
        @(posedge clk_i);
        #1;

        $display("RUN_TEST dual_pipeline_continuous_issue");
        reset_dut();
        for (index = 0; index < 4; index = index + 1) begin
            command_a[index] = make_cmd(OPCODE_WRITE, 1'b0, index[4:0],
                                        6'b0, 15'd180 + index, 1'b0, 1'b0);
            command_b[index] = make_cmd(OPCODE_WRITE, 1'b1,
                                        (index + 8), 6'b0,
                                        15'd190 + index, 1'b0, 1'b0);
            set_sr_selector(1'b0, index[4:0], 4'b1111,
                            pack_segments(64'h1000 + index,
                                          64'h1100 + index,
                                          64'h1200 + index,
                                          64'h1300 + index));
            set_sr_selector(1'b1, (index + 8), 4'b1111,
                            pack_segments(64'h2000 + index,
                                          64'h2100 + index,
                                          64'h2200 + index,
                                          64'h2300 + index));
        end
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            apply_cycle(2'b11, command_a[cycle], command_b[cycle]);
            if (cycle == 3) begin
                if (count_consume() != 8 || bank_pipeline_busy_o !== 2'b11) begin
                    $display("ERROR continuous steady-state access count");
                    errors = errors + 1;
                end
                for (tile = 0; tile < 4; tile = tile + 1) begin
                    cell0 = consume_cell(0, 1'b0, (3-tile), tile);
                    cell1 = consume_cell(1, 1'b1, (11-tile), tile);
                    if (!sr_consume_o[cell0] || !sr_consume_o[cell1]) begin
                        $display("ERROR continuous selector tile%0d", tile);
                        errors = errors + 1;
                    end
                end
                if (!bank_north_cmd_valid_o[0] ||
                    !bank_north_cmd_valid_o[1] ||
                    bank_north_cmd_o[31:0] !== command_a[0] ||
                    bank_north_cmd_o[63:32] !== command_b[0]) begin
                    $display("ERROR continuous north order first command");
                    errors = errors + 1;
                end
            end
        end
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            idle_cycle();
            if (cycle < 3) begin
                if (!bank_north_cmd_valid_o[0] ||
                    !bank_north_cmd_valid_o[1] ||
                    bank_north_cmd_o[31:0] !== command_a[cycle + 1] ||
                    bank_north_cmd_o[63:32] !== command_b[cycle + 1]) begin
                    $display("ERROR continuous north order cycle%0d", cycle);
                    errors = errors + 1;
                end
            end else if (bank_north_cmd_valid_o !== 2'b00) begin
                $display("ERROR continuous north trace did not drain");
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
