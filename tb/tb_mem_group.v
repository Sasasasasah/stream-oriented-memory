`timescale 1ns/1ps

module tb_mem_group;

    localparam [2:0] OPCODE_READ  = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;
    localparam [2:0] FAULT_COLLISION = 3'd3;

    reg          clk_i;
    reg          rst_ni;
    reg  [7:0]   group_issue_valid_i;
    reg  [255:0] group_issue_i;
    reg  [255:0] left_boundary_state_valid_i;
    reg  [16383:0] left_boundary_state_data_i;
    reg  [255:0] right_boundary_state_valid_i;
    reg  [16383:0] right_boundary_state_data_i;
    reg  [31:0]  external_producer_collision_i;

    wire [255:0] left_boundary_consume_o;
    wire [255:0] right_boundary_consume_o;
    wire [31:0]  left_boundary_inject_valid_o;
    wire [31:0]  right_boundary_inject_valid_o;
    wire [2047:0] boundary_inject_data_o;
    wire [31:0]  boundary_inject_stream_dir_o;
    wire [159:0] boundary_inject_stream_idx_o;
    wire [31:0]  internal_mem_collision_o;
    wire [7:0]   slice_fault_valid_o;
    wire [23:0]  slice_fault_code_o;
    wire [7:0]   slice_fault_bank_id_o;
    wire [7:0]   slice_fault_tile_valid_o;
    wire [15:0]  slice_fault_tile_id_o;
    wire [119:0] slice_fault_row_o;
    wire         group_fault_valid_o;
    wire [3:0]   slice_busy_o;
    wire         group_busy_o;

    integer errors;
    integer slice_index;
    integer bank_index;
    integer tile;
    integer cycle;
    integer entry;
    integer cell_index;

    mem_group dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .group_issue_valid_i(group_issue_valid_i),
        .group_issue_i(group_issue_i),
        .left_boundary_state_valid_i(left_boundary_state_valid_i),
        .left_boundary_state_data_i(left_boundary_state_data_i),
        .right_boundary_state_valid_i(right_boundary_state_valid_i),
        .right_boundary_state_data_i(right_boundary_state_data_i),
        .external_producer_collision_i(external_producer_collision_i),
        .left_boundary_consume_o(left_boundary_consume_o),
        .right_boundary_consume_o(right_boundary_consume_o),
        .left_boundary_inject_valid_o(left_boundary_inject_valid_o),
        .right_boundary_inject_valid_o(right_boundary_inject_valid_o),
        .boundary_inject_data_o(boundary_inject_data_o),
        .boundary_inject_stream_dir_o(boundary_inject_stream_dir_o),
        .boundary_inject_stream_idx_o(boundary_inject_stream_idx_o),
        .internal_mem_collision_o(internal_mem_collision_o),
        .slice_fault_valid_o(slice_fault_valid_o),
        .slice_fault_code_o(slice_fault_code_o),
        .slice_fault_bank_id_o(slice_fault_bank_id_o),
        .slice_fault_tile_valid_o(slice_fault_tile_valid_o),
        .slice_fault_tile_id_o(slice_fault_tile_id_o),
        .slice_fault_row_o(slice_fault_row_o),
        .group_fault_valid_o(group_fault_valid_o),
        .slice_busy_o(slice_busy_o),
        .group_busy_o(group_busy_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [31:0] make_cmd;
        input [2:0] opcode;
        input       direction;
        input [4:0] stream_index;
        input [14:0] row;
        input       preserve;
        begin
            make_cmd = 32'b0;
            make_cmd[2:0] = opcode;
            make_cmd[8:3] = {direction, stream_index};
            make_cmd[29:15] = row;
            make_cmd[31] = preserve;
        end
    endfunction

    function integer issue_entry;
        input integer slice_id;
        input integer bank_id;
        begin
            issue_entry = slice_id*2 + bank_id;
        end
    endfunction

    function integer candidate_entry;
        input integer slice_id;
        input integer bank_id;
        input integer tile_id;
        begin
            candidate_entry = slice_id*8 + bank_id*4 + tile_id;
        end
    endfunction

    function integer boundary_cell;
        input       direction;
        input [4:0] stream_index;
        input integer tile_id;
        begin
            boundary_cell = (direction ? 128 : 0) +
                            stream_index*4 + tile_id;
        end
    endfunction

    function integer count_left_consume;
        integer bit_index;
        begin
            count_left_consume = 0;
            for (bit_index = 0; bit_index < 256; bit_index = bit_index + 1)
                count_left_consume = count_left_consume +
                                     left_boundary_consume_o[bit_index];
        end
    endfunction

    function integer count_right_consume;
        integer bit_index;
        begin
            count_right_consume = 0;
            for (bit_index = 0; bit_index < 256; bit_index = bit_index + 1)
                count_right_consume = count_right_consume +
                                      right_boundary_consume_o[bit_index];
        end
    endfunction

    function integer count_left_inject;
        integer bit_index;
        begin
            count_left_inject = 0;
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
                count_left_inject = count_left_inject +
                                    left_boundary_inject_valid_o[bit_index];
        end
    endfunction

    function integer count_right_inject;
        integer bit_index;
        begin
            count_right_inject = 0;
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
                count_right_inject = count_right_inject +
                                     right_boundary_inject_valid_o[bit_index];
        end
    endfunction

    function integer count_collision;
        integer bit_index;
        begin
            count_collision = 0;
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
                count_collision = count_collision +
                                  internal_mem_collision_o[bit_index];
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

    task clear_boundary_state;
        begin
            left_boundary_state_valid_i = 256'b0;
            left_boundary_state_data_i = 16384'b0;
            right_boundary_state_valid_i = 256'b0;
            right_boundary_state_data_i = 16384'b0;
        end
    endtask

    task set_boundary_selector;
        input       use_left;
        input       direction;
        input [4:0] stream_index;
        input [3:0] valid_mask;
        input [255:0] segments;
        integer local_tile;
        integer local_cell;
        begin
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                local_cell = boundary_cell(direction, stream_index, local_tile);
                if (use_left) begin
                    left_boundary_state_valid_i[local_cell] =
                        valid_mask[local_tile];
                    left_boundary_state_data_i[local_cell*64 +: 64] =
                        segments[local_tile*64 +: 64];
                end else begin
                    right_boundary_state_valid_i[local_cell] =
                        valid_mask[local_tile];
                    right_boundary_state_data_i[local_cell*64 +: 64] =
                        segments[local_tile*64 +: 64];
                end
            end
        end
    endtask

    task apply_cycle;
        input [7:0] valid_mask;
        input [255:0] command_bus;
        begin
            @(negedge clk_i);
            group_issue_valid_i = valid_mask;
            group_issue_i = command_bus;
            @(posedge clk_i);
            #1;
        end
    endtask

    task idle_cycle;
        begin
            apply_cycle(8'b0, 256'b0);
        end
    endtask

    task reset_dut;
        begin
            group_issue_valid_i = 8'b0;
            group_issue_i = 256'b0;
            external_producer_collision_i = 32'b0;
            clear_boundary_state();
            rst_ni = 1'b0;
            #1;
            if (slice_busy_o !== 4'b0 || group_busy_o !== 1'b0 ||
                group_fault_valid_o !== 1'b0 ||
                left_boundary_consume_o !== 256'b0 ||
                right_boundary_consume_o !== 256'b0 ||
                left_boundary_inject_valid_o !== 32'b0 ||
                right_boundary_inject_valid_o !== 32'b0) begin
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
        input integer slice_id;
        input integer bank_id;
        input [14:0] row;
        input       direction;
        input [4:0] stream_index;
        input [255:0] segments;
        reg [255:0] commands;
        reg [7:0] valids;
        integer local_cycle;
        integer local_entry;
        begin
            set_boundary_selector(!direction, direction, stream_index,
                                  4'b1111, segments);
            local_entry = issue_entry(slice_id, bank_id);
            commands = 256'b0;
            commands[local_entry*32 +: 32] =
                make_cmd(OPCODE_WRITE, direction, stream_index, row, 1'b0);
            for (local_cycle = 0; local_cycle < 4;
                 local_cycle = local_cycle + 1) begin
                valids = 8'b0;
                if (local_cycle == 0)
                    valids[local_entry] = 1'b1;
                apply_cycle(valids, commands);
            end
        end
    endtask

    task check_readback;
        input integer slice_id;
        input integer bank_id;
        input [14:0] row;
        input       direction;
        input [4:0] stream_index;
        input [255:0] expected;
        input [8*48-1:0] test_name;
        reg [255:0] commands;
        reg [7:0] valids;
        integer local_tile;
        integer local_issue;
        integer local_candidate;
        begin
            local_issue = issue_entry(slice_id, bank_id);
            commands = 256'b0;
            commands[local_issue*32 +: 32] =
                make_cmd(OPCODE_READ, direction, stream_index, row, 1'b0);
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                valids = 8'b0;
                if (local_tile == 0)
                    valids[local_issue] = 1'b1;
                apply_cycle(valids, commands);
                local_candidate = candidate_entry(slice_id, bank_id,
                                                   local_tile);
                if ((direction ? left_boundary_inject_valid_o[local_candidate]
                               : right_boundary_inject_valid_o[local_candidate])
                    !== 1'b1 ||
                    boundary_inject_data_o[local_candidate*64 +: 64] !==
                        expected[local_tile*64 +: 64] ||
                    boundary_inject_stream_idx_o[local_candidate*5 +: 5] !==
                        stream_index) begin
                    $display("ERROR %0s tile%0d readback mismatch",
                             test_name, local_tile);
                    errors = errors + 1;
                end
            end
        end
    endtask

    reg [255:0] data0;
    reg [255:0] data1;
    reg [255:0] data2;
    reg [255:0] data3;
    reg [255:0] commands;
    reg [7:0] valids;
    reg [31:0] cmd_east;
    reg [31:0] cmd_west;

    initial begin
        errors = 0;
        rst_ni = 1'b1;
        group_issue_valid_i = 8'b0;
        group_issue_i = 256'b0;
        external_producer_collision_i = 32'b0;
        clear_boundary_state();

        data0 = pack_segments(64'h1000, 64'h1001, 64'h1002, 64'h1003);
        data1 = pack_segments(64'h2000, 64'h2001, 64'h2002, 64'h2003);
        data2 = pack_segments(64'h3000, 64'h3001, 64'h3002, 64'h3003);
        data3 = pack_segments(64'h4000, 64'h4001, 64'h4002, 64'h4003);

        $display("RUN_TEST four_slice_independence");
        reset_dut();
        commands = 256'b0;
        valids = 8'b0;
        for (slice_index = 0; slice_index < 4;
             slice_index = slice_index + 1) begin
            set_boundary_selector(1'b1, 1'b0, slice_index[4:0],
                                  4'b1111,
                                  slice_index == 0 ? data0 :
                                  slice_index == 1 ? data1 :
                                  slice_index == 2 ? data2 : data3);
            entry = issue_entry(slice_index, 0);
            valids[entry] = 1'b1;
            commands[entry*32 +: 32] =
                make_cmd(OPCODE_WRITE, 1'b0, slice_index[4:0],
                         15'd100 + slice_index, 1'b0);
        end
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 8'b0, commands);
            if (count_left_consume() != 4 ||
                right_boundary_consume_o !== 256'b0 ||
                slice_busy_o !== (tile == 3 ? 4'b0000 : 4'b1111)) begin
                $display("ERROR four-slice independence tile%0d", tile);
                errors = errors + 1;
            end
        end
        check_readback(0, 0, 15'd100, 1'b0, 5'd16, data0,
                       "slice0_independent");
        check_readback(1, 0, 15'd101, 1'b0, 5'd17, data1,
                       "slice1_independent");
        check_readback(2, 0, 15'd102, 1'b0, 5'd18, data2,
                       "slice2_independent");
        check_readback(3, 0, 15'd103, 1'b0, 5'd19, data3,
                       "slice3_independent");

        $display("RUN_TEST east_write_mapping");
        reset_dut();
        set_boundary_selector(1'b1, 1'b0, 5'd3, 4'b1111, data0);
        set_boundary_selector(1'b0, 1'b0, 5'd3, 4'b1111, data1);
        setup_write(0, 0, 15'd200, 1'b0, 5'd3, data0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            cell_index = boundary_cell(1'b0, 5'd3, tile);
            // setup_write completed; verify the source through readback below.
        end
        check_readback(0, 0, 15'd200, 1'b0, 5'd20, data0,
                       "east_write_from_left");

        $display("RUN_TEST west_write_mapping");
        reset_dut();
        set_boundary_selector(1'b1, 1'b1, 5'd4, 4'b1111, data0);
        set_boundary_selector(1'b0, 1'b1, 5'd4, 4'b1111, data1);
        setup_write(1, 0, 15'd201, 1'b1, 5'd4, data1);
        check_readback(1, 0, 15'd201, 1'b1, 5'd21, data1,
                       "west_write_from_right");

        $display("RUN_TEST east_west_read_mapping");
        reset_dut();
        commands = 256'b0;
        valids = 8'b0;
        cmd_east = make_cmd(OPCODE_READ, 1'b0, 5'd6, 15'd200, 1'b0);
        cmd_west = make_cmd(OPCODE_READ, 1'b1, 5'd7, 15'd201, 1'b0);
        commands[issue_entry(0,0)*32 +: 32] = cmd_east;
        commands[issue_entry(1,0)*32 +: 32] = cmd_west;
        valids[issue_entry(0,0)] = 1'b1;
        valids[issue_entry(1,0)] = 1'b1;
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 8'b0, commands);
            if (!right_boundary_inject_valid_o[candidate_entry(0,0,tile)] ||
                left_boundary_inject_valid_o[candidate_entry(0,0,tile)] ||
                !left_boundary_inject_valid_o[candidate_entry(1,0,tile)] ||
                right_boundary_inject_valid_o[candidate_entry(1,0,tile)]) begin
                $display("ERROR East/West Read boundary tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST broadcast_consume");
        reset_dut();
        set_boundary_selector(1'b1, 1'b0, 5'd8, 4'b1111, data2);
        commands = 256'b0;
        valids = 8'hFF;
        for (entry = 0; entry < 8; entry = entry + 1)
            commands[entry*32 +: 32] =
                make_cmd(OPCODE_WRITE, 1'b0, 5'd8,
                         15'd300 + entry, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 8'b0, commands);
            cell_index = boundary_cell(1'b0, 5'd8, tile);
            if (!left_boundary_consume_o[cell_index] ||
                count_left_consume() != 1 || count_collision() != 0 ||
                group_fault_valid_o) begin
                $display("ERROR broadcast consume tile%0d", tile);
                errors = errors + 1;
            end
        end
        for (slice_index = 0; slice_index < 4;
             slice_index = slice_index + 1)
            for (bank_index = 0; bank_index < 2;
                 bank_index = bank_index + 1)
                check_readback(slice_index, bank_index,
                               15'd300 + issue_entry(slice_index,bank_index),
                               1'b0, 5'd22, data2, "broadcast_write_data");

        $display("RUN_TEST parallel_nonconflicting_reads");
        reset_dut();
        commands = 256'b0;
        valids = 8'b0;
        for (slice_index = 0; slice_index < 4;
             slice_index = slice_index + 1) begin
            entry = issue_entry(slice_index, 0);
            valids[entry] = 1'b1;
            commands[entry*32 +: 32] =
                make_cmd(OPCODE_READ, slice_index[0],
                         5'd10 + slice_index,
                         15'd300 + entry, 1'b0);
        end
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 8'b0, commands);
            if (count_left_inject() != 2 || count_right_inject() != 2 ||
                count_collision() != 0 || group_fault_valid_o) begin
                $display("ERROR non-conflicting Reads tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST intra_group_producer_collision");
        reset_dut();
        commands = 256'b0;
        valids = 8'b0;
        commands[issue_entry(0,0)*32 +: 32] =
            make_cmd(OPCODE_READ, 1'b0, 5'd14, 15'd300, 1'b0);
        commands[issue_entry(2,1)*32 +: 32] =
            make_cmd(OPCODE_READ, 1'b0, 5'd14, 15'd305, 1'b0);
        valids[issue_entry(0,0)] = 1'b1;
        valids[issue_entry(2,1)] = 1'b1;
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 8'b0, commands);
            if (!internal_mem_collision_o[candidate_entry(0,0,tile)] ||
                !internal_mem_collision_o[candidate_entry(2,1,tile)] ||
                !right_boundary_inject_valid_o[candidate_entry(0,0,tile)] ||
                !right_boundary_inject_valid_o[candidate_entry(2,1,tile)] ||
                slice_fault_code_o[issue_entry(0,0)*3 +: 3] !==
                    FAULT_COLLISION ||
                slice_fault_code_o[issue_entry(2,1)*3 +: 3] !==
                    FAULT_COLLISION) begin
                $display("ERROR local collision tile%0d", tile);
                errors = errors + 1;
            end
        end
        // External collision uses the same preserved candidate identity.
        reset_dut();
        external_producer_collision_i[candidate_entry(1,0,0)] = 1'b1;
        commands = 256'b0;
        commands[issue_entry(1,0)*32 +: 32] =
            make_cmd(OPCODE_READ, 1'b1, 5'd15, 15'd302, 1'b0);
        apply_cycle(8'b00000100, commands);
        if (!left_boundary_inject_valid_o[candidate_entry(1,0,0)] ||
            slice_fault_code_o[issue_entry(1,0)*3 +: 3] !==
                FAULT_COLLISION) begin
            $display("ERROR external collision feedback");
            errors = errors + 1;
        end
        external_producer_collision_i = 32'b0;

        $display("RUN_TEST continuous_mixed_traffic");
        reset_dut();
        // Existing broadcast rows 300/301 supply slice0 Read traffic.
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            set_boundary_selector(1'b1, 1'b0, cycle[4:0],
                                  4'b1111, data0);
            set_boundary_selector(1'b0, 1'b1, (cycle+4),
                                  4'b1111, data1);
            set_boundary_selector(1'b1, 1'b0, (cycle+8),
                                  4'b1111, data2);
            set_boundary_selector(1'b0, 1'b1, (cycle+12),
                                  4'b1111, data3);
        end
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            commands = 256'b0;
            valids = 8'b00111111; // slice3 is a bubble on both banks.
            commands[issue_entry(0,0)*32 +: 32] =
                make_cmd(OPCODE_READ, 1'b0, 5'd20 + cycle,
                         15'd300, 1'b0);
            commands[issue_entry(0,1)*32 +: 32] =
                make_cmd(OPCODE_READ, 1'b1, 5'd24 + cycle,
                         15'd301, 1'b0);
            commands[issue_entry(1,0)*32 +: 32] =
                make_cmd(OPCODE_WRITE, 1'b0, cycle[4:0],
                         15'd400 + cycle, 1'b0);
            commands[issue_entry(1,1)*32 +: 32] =
                make_cmd(OPCODE_WRITE, 1'b1, (cycle+4),
                         15'd410 + cycle, 1'b0);
            commands[issue_entry(2,0)*32 +: 32] =
                make_cmd(OPCODE_WRITE, 1'b0, (cycle+8),
                         15'd420 + cycle, 1'b1);
            commands[issue_entry(2,1)*32 +: 32] =
                make_cmd(OPCODE_WRITE, 1'b1, (cycle+12),
                         15'd430 + cycle, 1'b1);
            apply_cycle(valids, commands);
            if (cycle == 3) begin
                if (count_left_inject() != 4 || count_right_inject() != 4 ||
                    count_left_consume() != 4 ||
                    count_right_consume() != 4 ||
                    count_collision() != 0 || group_fault_valid_o ||
                    slice_busy_o !== 4'b0111) begin
                    $display("ERROR mixed steady-state traffic");
                    errors = errors + 1;
                end
            end
        end
        for (cycle = 0; cycle < 3; cycle = cycle + 1) begin
            idle_cycle();
            if (count_left_inject() != (3-cycle) ||
                count_right_inject() != (3-cycle) ||
                count_left_consume() != (3-cycle) ||
                count_right_consume() != (3-cycle) ||
                count_collision() != 0 || group_fault_valid_o) begin
                $display("ERROR mixed traffic drain cycle%0d", cycle);
                errors = errors + 1;
            end
        end
        rst_ni = 1'b0;
        #1;
        if (group_busy_o || group_fault_valid_o ||
            left_boundary_inject_valid_o !== 32'b0 ||
            right_boundary_inject_valid_o !== 32'b0) begin
            $display("ERROR group reset did not clear transient state");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
