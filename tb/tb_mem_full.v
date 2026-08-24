`timescale 1ns/1ps

module tb_mem_full;

    localparam P_TEST_DEPTH = 16;
    localparam [2:0] OPCODE_READ = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;

    reg clk_i;
    reg [1:0] rst_ni;
    reg [207:0] bank_issue_valid_i;
    reg [6655:0] bank_issue_i;
    reg [7167:0] boundary_state_valid_i;
    reg [458751:0] boundary_state_data_i;
    reg [11647:0] external_producer_collision_i;

    wire [7167:0] boundary_consume_o;
    wire [831:0] producer_valid_o;
    wire [53247:0] producer_data_o;
    wire [831:0] producer_stream_dir_o;
    wire [4159:0] producer_stream_idx_o;
    wire [3327:0] producer_boundary_o;
    wire [831:0] internal_mem_collision_o;
    wire [207:0] bank_fault_valid_o;
    wire [623:0] bank_fault_code_o;
    wire [207:0] bank_fault_tile_valid_o;
    wire [415:0] bank_fault_tile_id_o;
    wire [3119:0] bank_fault_row_o;
    wire [25:0] group_fault_valid_o;
    wire [1:0] hemisphere_fault_valid_o;
    wire [25:0] group_busy_o;
    wire [1:0] hemisphere_busy_o;

    integer errors;
    integer tile;
    integer cycle;
    reg [207:0] valids;
    reg [6655:0] commands;
    reg [255:0] west_data;
    reg [255:0] east_data;
    reg [255:0] traffic_data;

    mem_full #(
        .P_MEM_SLICES_PER_HEMI(52),
        .P_MEM_SLICES_PER_GROUP(4),
        .P_MEM_BANK_DEPTH_ROWS(P_TEST_DEPTH)
    ) dut (
        .clk_i(clk_i),
        .west_rst_ni(rst_ni[0]),
        .east_rst_ni(rst_ni[1]),
        .west_bank_issue_valid_i(bank_issue_valid_i[0 +: 104]),
        .west_bank_issue_i(bank_issue_i[0 +: 3328]),
        .west_mem_boundary_state_valid_i(
            boundary_state_valid_i[0 +: 3584]),
        .west_mem_boundary_state_data_i(
            boundary_state_data_i[0 +: 229376]),
        .west_external_producer_collision_i(
            external_producer_collision_i[0 +: 5824]),
        .west_mem_boundary_consume_o(boundary_consume_o[0 +: 3584]),
        .west_producer_valid_o(producer_valid_o[0 +: 416]),
        .west_producer_data_o(producer_data_o[0 +: 26624]),
        .west_producer_stream_dir_o(producer_stream_dir_o[0 +: 416]),
        .west_producer_stream_idx_o(producer_stream_idx_o[0 +: 2080]),
        .west_producer_boundary_o(producer_boundary_o[0 +: 1664]),
        .west_internal_mem_collision_o(
            internal_mem_collision_o[0 +: 416]),
        .west_bank_fault_valid_o(bank_fault_valid_o[0 +: 104]),
        .west_bank_fault_code_o(bank_fault_code_o[0 +: 312]),
        .west_bank_fault_tile_valid_o(
            bank_fault_tile_valid_o[0 +: 104]),
        .west_bank_fault_tile_id_o(bank_fault_tile_id_o[0 +: 208]),
        .west_bank_fault_row_o(bank_fault_row_o[0 +: 1560]),
        .west_group_fault_valid_o(group_fault_valid_o[0 +: 13]),
        .west_hemisphere_fault_valid_o(hemisphere_fault_valid_o[0]),
        .west_group_busy_o(group_busy_o[0 +: 13]),
        .west_hemisphere_busy_o(hemisphere_busy_o[0]),
        .east_bank_issue_valid_i(bank_issue_valid_i[104 +: 104]),
        .east_bank_issue_i(bank_issue_i[3328 +: 3328]),
        .east_mem_boundary_state_valid_i(
            boundary_state_valid_i[3584 +: 3584]),
        .east_mem_boundary_state_data_i(
            boundary_state_data_i[229376 +: 229376]),
        .east_external_producer_collision_i(
            external_producer_collision_i[5824 +: 5824]),
        .east_mem_boundary_consume_o(boundary_consume_o[3584 +: 3584]),
        .east_producer_valid_o(producer_valid_o[416 +: 416]),
        .east_producer_data_o(producer_data_o[26624 +: 26624]),
        .east_producer_stream_dir_o(producer_stream_dir_o[416 +: 416]),
        .east_producer_stream_idx_o(producer_stream_idx_o[2080 +: 2080]),
        .east_producer_boundary_o(producer_boundary_o[1664 +: 1664]),
        .east_internal_mem_collision_o(
            internal_mem_collision_o[416 +: 416]),
        .east_bank_fault_valid_o(bank_fault_valid_o[104 +: 104]),
        .east_bank_fault_code_o(bank_fault_code_o[312 +: 312]),
        .east_bank_fault_tile_valid_o(
            bank_fault_tile_valid_o[104 +: 104]),
        .east_bank_fault_tile_id_o(bank_fault_tile_id_o[208 +: 208]),
        .east_bank_fault_row_o(bank_fault_row_o[1560 +: 1560]),
        .east_group_fault_valid_o(group_fault_valid_o[13 +: 13]),
        .east_hemisphere_fault_valid_o(hemisphere_fault_valid_o[1]),
        .east_group_busy_o(group_busy_o[13 +: 13]),
        .east_hemisphere_busy_o(hemisphere_busy_o[1])
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [31:0] make_cmd;
        input [2:0] opcode;
        input direction;
        input [4:0] stream_index;
        input [14:0] row;
        input preserve;
        begin
            make_cmd = 32'b0;
            make_cmd[2:0] = opcode;
            make_cmd[8:3] = {direction, stream_index};
            make_cmd[29:15] = row;
            make_cmd[31] = preserve;
        end
    endfunction

    function integer issue_id;
        input integer side;
        input integer slice_id;
        input integer bank_id;
        begin
            issue_id = side*104 + slice_id*2 + bank_id;
        end
    endfunction

    function integer producer_id;
        input integer side;
        input integer slice_id;
        input integer bank_id;
        input integer tile_id;
        begin
            producer_id = side*416 + slice_id*8 + bank_id*4 + tile_id;
        end
    endfunction

    function integer boundary_cell;
        input integer side;
        input integer boundary_id;
        input direction;
        input [4:0] stream_index;
        input integer tile_id;
        begin
            boundary_cell = side*3584 + boundary_id*256 +
                            (direction ? 128 : 0) +
                            stream_index*4 + tile_id;
        end
    endfunction

    function integer count_side_producers;
        input integer side;
        integer bit_id;
        begin
            count_side_producers = 0;
            for (bit_id = 0; bit_id < 416; bit_id = bit_id + 1)
                count_side_producers = count_side_producers +
                    producer_valid_o[side*416 + bit_id];
        end
    endfunction

    function integer count_side_consume;
        input integer side;
        integer bit_id;
        begin
            count_side_consume = 0;
            for (bit_id = 0; bit_id < 3584; bit_id = bit_id + 1)
                count_side_consume = count_side_consume +
                    boundary_consume_o[side*3584 + bit_id];
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

    task set_boundary_selector;
        input integer side;
        input integer boundary_id;
        input direction;
        input [4:0] stream_index;
        input [3:0] valid_mask;
        input [255:0] segments;
        integer local_tile;
        integer cell_index_local;
        begin
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                cell_index_local = boundary_cell(side, boundary_id,
                    direction, stream_index, local_tile);
                boundary_state_valid_i[cell_index_local] =
                    valid_mask[local_tile];
                boundary_state_data_i[cell_index_local*64 +: 64] =
                    segments[local_tile*64 +: 64];
            end
        end
    endtask

    task apply_cycle;
        input [207:0] valid_mask;
        input [6655:0] command_bus;
        begin
            @(negedge clk_i);
            bank_issue_valid_i = valid_mask;
            bank_issue_i = command_bus;
            @(posedge clk_i);
            #1;
        end
    endtask

    task idle_cycle;
        begin
            apply_cycle(208'b0, 6656'b0);
        end
    endtask

    task reset_both;
        begin
            bank_issue_valid_i = 208'b0;
            bank_issue_i = 6656'b0;
            boundary_state_valid_i = 7168'b0;
            boundary_state_data_i = 458752'b0;
            external_producer_collision_i = 11648'b0;
            rst_ni = 2'b00;
            #1;
            if (hemisphere_busy_o !== 2'b00 ||
                hemisphere_fault_valid_o !== 2'b00 ||
                producer_valid_o !== 832'b0 ||
                boundary_consume_o !== 7168'b0) begin
                $display("ERROR dual reset outputs not idle");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 2'b11;
            @(posedge clk_i);
            #1;
        end
    endtask

    task setup_write;
        input integer side;
        input integer slice_id;
        input integer bank_id;
        input [14:0] row;
        input direction;
        input [4:0] stream_index;
        input [255:0] segments;
        integer group_id;
        integer input_boundary;
        integer local_cycle;
        integer issue;
        reg [207:0] local_valid;
        reg [6655:0] local_commands;
        begin
            group_id = slice_id / 4;
            input_boundary = direction ? group_id + 1 : group_id;
            set_boundary_selector(side, input_boundary, direction,
                                  stream_index, 4'b1111, segments);
            issue = issue_id(side, slice_id, bank_id);
            local_commands = 6656'b0;
            local_commands[issue*32 +: 32] =
                make_cmd(OPCODE_WRITE, direction, stream_index, row, 1'b0);
            for (local_cycle = 0; local_cycle < 4;
                 local_cycle = local_cycle + 1) begin
                local_valid = 208'b0;
                if (local_cycle == 0)
                    local_valid[issue] = 1'b1;
                apply_cycle(local_valid, local_commands);
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 2'b11;
        bank_issue_valid_i = 208'b0;
        bank_issue_i = 6656'b0;
        boundary_state_valid_i = 7168'b0;
        boundary_state_data_i = 458752'b0;
        external_producer_collision_i = 11648'b0;
        west_data = pack_segments(64'h110,64'h111,64'h112,64'h113);
        east_data = pack_segments(64'h220,64'h221,64'h222,64'h223);
        traffic_data = pack_segments(64'h330,64'h331,64'h332,64'h333);

        $display("RUN_TEST dual_hemisphere_reset");
        reset_both();
        // Fill both control pipelines, then reset only West. East must retain
        // its in-flight command while West becomes idle immediately.
        valids = 208'b0;
        commands = 6656'b0;
        valids[issue_id(0,0,0)] = 1'b1;
        valids[issue_id(1,0,0)] = 1'b1;
        commands[issue_id(0,0,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b0,5'd1,15'd0,1'b0);
        commands[issue_id(1,0,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b0,5'd2,15'd0,1'b0);
        apply_cycle(valids, commands);
        rst_ni[0] = 1'b0;
        #1;
        if (hemisphere_busy_o[0] || count_side_producers(0) != 0 ||
            !hemisphere_busy_o[1]) begin
            $display("ERROR independent West reset");
            errors = errors + 1;
        end
        rst_ni[1] = 1'b0;
        #1;
        rst_ni = 2'b11;
        idle_cycle();

        $display("RUN_TEST independent_write");
        reset_both();
        set_boundary_selector(0,0,1'b0,5'd3,4'b1111,west_data);
        set_boundary_selector(1,0,1'b0,5'd4,4'b1111,east_data);
        commands = 6656'b0;
        commands[issue_id(0,0,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b0,5'd3,15'd1,1'b0);
        commands[issue_id(1,0,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b0,5'd4,15'd1,1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            valids = 208'b0;
            if (tile == 0) begin
                valids[issue_id(0,0,0)] = 1'b1;
                valids[issue_id(1,0,0)] = 1'b1;
            end
            apply_cycle(valids, commands);
            if (!boundary_consume_o[boundary_cell(0,0,1'b0,5'd3,tile)] ||
                !boundary_consume_o[boundary_cell(1,0,1'b0,5'd4,tile)]) begin
                $display("ERROR independent Write consume tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST independent_read");
        commands = 6656'b0;
        commands[issue_id(0,0,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b0,5'd10,15'd1,1'b0);
        commands[issue_id(1,0,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b0,5'd11,15'd1,1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            valids = 208'b0;
            if (tile == 0) begin
                valids[issue_id(0,0,0)] = 1'b1;
                valids[issue_id(1,0,0)] = 1'b1;
            end
            apply_cycle(valids, commands);
            if (!producer_valid_o[producer_id(0,0,0,tile)] ||
                !producer_valid_o[producer_id(1,0,0,tile)] ||
                producer_data_o[producer_id(0,0,0,tile)*64 +: 64] !==
                    west_data[tile*64 +: 64] ||
                producer_data_o[producer_id(1,0,0,tile)*64 +: 64] !==
                    east_data[tile*64 +: 64] ||
                count_side_producers(0) != 1 ||
                count_side_producers(1) != 1) begin
                $display("ERROR independent Read tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST parameter_consistency");
        if (dut.u_west_mem_hemisphere.P_MEM_SLICES_PER_HEMI !==
                dut.u_east_mem_hemisphere.P_MEM_SLICES_PER_HEMI ||
            dut.u_west_mem_hemisphere.P_MEM_SLICES_PER_GROUP !==
                dut.u_east_mem_hemisphere.P_MEM_SLICES_PER_GROUP ||
            dut.u_west_mem_hemisphere.P_MEM_BANK_DEPTH_ROWS !==
                dut.u_east_mem_hemisphere.P_MEM_BANK_DEPTH_ROWS ||
            dut.u_west_mem_hemisphere.P_MEM_SLICES_PER_HEMI !== 52 ||
            dut.u_west_mem_hemisphere.P_MEM_BANK_DEPTH_ROWS !== P_TEST_DEPTH) begin
            $display("ERROR West/East parameter consistency");
            errors = errors + 1;
        end

        $display("RUN_TEST parallel_mixed_traffic");
        reset_both();
        setup_write(0,0,0,15'd2,1'b0,5'd5,west_data);
        setup_write(1,48,0,15'd3,1'b1,5'd6,east_data);
        set_boundary_selector(0,6,1'b0,5'd7,4'b1111,traffic_data);
        set_boundary_selector(0,6,1'b0,5'd8,4'b1111,traffic_data);
        set_boundary_selector(1,13,1'b1,5'd9,4'b1111,traffic_data);
        set_boundary_selector(1,13,1'b1,5'd10,4'b1111,traffic_data);
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            valids = 208'b0;
            commands = 6656'b0;
            if (cycle == 0) begin
                valids[issue_id(0,0,0)] = 1'b1;
                valids[issue_id(1,51,0)] = 1'b1;
                commands[issue_id(0,0,0)*32 +: 32] =
                    make_cmd(OPCODE_READ,1'b0,5'd20,15'd2,1'b0);
                commands[issue_id(1,51,0)*32 +: 32] =
                    make_cmd(OPCODE_WRITE,1'b1,5'd9,15'd4,1'b0);
            end else if (cycle == 1) begin
                valids[issue_id(0,24,0)] = 1'b1;
                valids[issue_id(1,48,0)] = 1'b1;
                commands[issue_id(0,24,0)*32 +: 32] =
                    make_cmd(OPCODE_WRITE,1'b0,5'd7,15'd5,1'b0);
                commands[issue_id(1,48,0)*32 +: 32] =
                    make_cmd(OPCODE_READ,1'b1,5'd21,15'd3,1'b0);
            end else if (cycle == 2) begin
                valids[issue_id(0,24,1)] = 1'b1;
                commands[issue_id(0,24,1)*32 +: 32] =
                    make_cmd(OPCODE_WRITE,1'b0,5'd8,15'd6,1'b1);
                // East bubble is intentional.
            end else begin
                valids[issue_id(1,51,1)] = 1'b1;
                commands[issue_id(1,51,1)*32 +: 32] =
                    make_cmd(OPCODE_WRITE,1'b1,5'd10,15'd7,1'b1);
                // West bubble is intentional.
            end
            apply_cycle(valids, commands);
            if (hemisphere_fault_valid_o !== 2'b00 ||
                internal_mem_collision_o !== 832'b0) begin
                $display("ERROR mixed traffic fault/collision cycle%0d", cycle);
                errors = errors + 1;
            end
            if (count_side_producers(0) != 1 ||
                count_side_consume(0) != (cycle == 0 ? 0 : 1) ||
                count_side_producers(1) != (cycle == 0 ? 0 : 1) ||
                count_side_consume(1) != 1) begin
                $display("ERROR mixed traffic side isolation cycle%0d", cycle);
                errors = errors + 1;
            end
            if (producer_data_o[
                    producer_id(0,0,0,cycle)*64 +: 64] !==
                    west_data[cycle*64 +: 64] ||
                (cycle != 0 && producer_data_o[
                    producer_id(1,48,0,cycle-1)*64 +: 64] !==
                    east_data[(cycle-1)*64 +: 64])) begin
                $display("ERROR mixed traffic producer data cycle%0d", cycle);
                errors = errors + 1;
            end
        end
        for (cycle = 0; cycle < 3; cycle = cycle + 1) begin
            idle_cycle();
            if (cycle == 0 &&
                (count_side_producers(0) != 0 ||
                 count_side_consume(0) != 1 ||
                 count_side_producers(1) != 1 ||
                 count_side_consume(1) != 0)) begin
                $display("ERROR mixed traffic first drain isolation");
                errors = errors + 1;
            end
        end
        if (hemisphere_busy_o !== 2'b00 ||
            hemisphere_fault_valid_o !== 2'b00) begin
            $display("ERROR mixed traffic busy drain");
            errors = errors + 1;
        end

        $display("RUN_TEST endpoint_isolation");
        reset_both();
        set_boundary_selector(0,0,1'b0,5'd12,4'b1111,west_data);
        commands = 6656'b0;
        valids = 208'b0;
        valids[issue_id(0,0,0)] = 1'b1;
        commands[issue_id(0,0,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b0,5'd12,15'd8,1'b0);
        apply_cycle(valids, commands);
        if (!boundary_consume_o[boundary_cell(0,0,1'b0,5'd12,0)] ||
            count_side_consume(1) != 0 || count_side_producers(1) != 0 ||
            hemisphere_busy_o[1] || hemisphere_fault_valid_o[1]) begin
            $display("ERROR West endpoint affected East");
            errors = errors + 1;
        end
        reset_both();
        set_boundary_selector(1,13,1'b1,5'd13,4'b1111,east_data);
        commands = 6656'b0;
        valids = 208'b0;
        valids[issue_id(1,51,1)] = 1'b1;
        commands[issue_id(1,51,1)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b1,5'd13,15'd9,1'b0);
        apply_cycle(valids, commands);
        if (!boundary_consume_o[boundary_cell(1,13,1'b1,5'd13,0)] ||
            count_side_consume(0) != 0 || count_side_producers(0) != 0 ||
            hemisphere_busy_o[0] || hemisphere_fault_valid_o[0]) begin
            $display("ERROR East endpoint affected West");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
