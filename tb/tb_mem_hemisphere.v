`timescale 1ns/1ps

module tb_mem_hemisphere;

    localparam P_TEST_DEPTH = 16;
    localparam [2:0] OPCODE_READ = 3'b000;
    localparam [2:0] OPCODE_WRITE = 3'b001;
    localparam [2:0] FAULT_COLLISION = 3'd3;

    reg clk_i;
    reg rst_ni;
    reg [103:0] bank_issue_valid_i;
    reg [3327:0] bank_issue_i;
    reg [3583:0] boundary_state_valid_i;
    reg [229375:0] boundary_state_data_i;
    reg [5823:0] external_producer_collision_i;

    wire [3583:0] boundary_consume_o;
    wire [415:0] producer_valid_o;
    wire [26623:0] producer_data_o;
    wire [415:0] producer_stream_dir_o;
    wire [2079:0] producer_stream_idx_o;
    wire [1663:0] producer_boundary_o;
    wire [415:0] internal_mem_collision_o;
    wire [103:0] bank_fault_valid_o;
    wire [311:0] bank_fault_code_o;
    wire [103:0] bank_fault_tile_valid_o;
    wire [207:0] bank_fault_tile_id_o;
    wire [1559:0] bank_fault_row_o;
    wire [12:0] group_fault_valid_o;
    wire hemisphere_fault_valid_o;
    wire [12:0] group_busy_o;
    wire hemisphere_busy_o;

    integer errors;
    integer tile;
    integer cycle;
    integer local_index;
    integer boundary_index;
    reg [103:0] valids;
    reg [3327:0] commands;
    reg [255:0] data0;
    reg [255:0] data1;
    reg [255:0] data2;

    mem_hemisphere #(
        .P_MEM_SLICES_PER_HEMI(52),
        .P_MEM_SLICES_PER_GROUP(4),
        .P_MEM_BANK_DEPTH_ROWS(P_TEST_DEPTH)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .bank_issue_valid_i(bank_issue_valid_i),
        .bank_issue_i(bank_issue_i),
        .boundary_state_valid_i(boundary_state_valid_i),
        .boundary_state_data_i(boundary_state_data_i),
        .external_producer_collision_i(external_producer_collision_i),
        .boundary_consume_o(boundary_consume_o),
        .producer_valid_o(producer_valid_o),
        .producer_data_o(producer_data_o),
        .producer_stream_dir_o(producer_stream_dir_o),
        .producer_stream_idx_o(producer_stream_idx_o),
        .producer_boundary_o(producer_boundary_o),
        .internal_mem_collision_o(internal_mem_collision_o),
        .bank_fault_valid_o(bank_fault_valid_o),
        .bank_fault_code_o(bank_fault_code_o),
        .bank_fault_tile_valid_o(bank_fault_tile_valid_o),
        .bank_fault_tile_id_o(bank_fault_tile_id_o),
        .bank_fault_row_o(bank_fault_row_o),
        .group_fault_valid_o(group_fault_valid_o),
        .hemisphere_fault_valid_o(hemisphere_fault_valid_o),
        .group_busy_o(group_busy_o),
        .hemisphere_busy_o(hemisphere_busy_o)
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
        input integer slice_id;
        input integer bank_id;
        begin
            issue_id = slice_id*2 + bank_id;
        end
    endfunction

    function integer producer_id;
        input integer slice_id;
        input integer bank_id;
        input integer tile_id;
        begin
            producer_id = slice_id*8 + bank_id*4 + tile_id;
        end
    endfunction

    function integer boundary_cell;
        input integer boundary_id;
        input direction;
        input [4:0] stream_index;
        input integer tile_id;
        begin
            boundary_cell = boundary_id*256 +
                            (direction ? 128 : 0) +
                            stream_index*4 + tile_id;
        end
    endfunction

    function integer count_producers;
        integer bit_id;
        begin
            count_producers = 0;
            for (bit_id = 0; bit_id < 416; bit_id = bit_id + 1)
                count_producers = count_producers + producer_valid_o[bit_id];
        end
    endfunction

    function integer count_boundary_consume;
        input integer boundary_id;
        integer bit_id;
        begin
            count_boundary_consume = 0;
            for (bit_id = 0; bit_id < 256; bit_id = bit_id + 1)
                count_boundary_consume = count_boundary_consume +
                    boundary_consume_o[boundary_id*256 + bit_id];
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
            boundary_state_valid_i = 3584'b0;
            boundary_state_data_i = 229376'b0;
        end
    endtask

    task set_boundary_selector;
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
                cell_index_local = boundary_cell(boundary_id, direction,
                                                 stream_index, local_tile);
                boundary_state_valid_i[cell_index_local] = valid_mask[local_tile];
                boundary_state_data_i[cell_index_local*64 +: 64] =
                    segments[local_tile*64 +: 64];
            end
        end
    endtask

    task apply_cycle;
        input [103:0] valid_mask;
        input [3327:0] command_bus;
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
            apply_cycle(104'b0, 3328'b0);
        end
    endtask

    task reset_dut;
        begin
            bank_issue_valid_i = 104'b0;
            bank_issue_i = 3328'b0;
            external_producer_collision_i = 5824'b0;
            clear_boundary_state();
            rst_ni = 1'b0;
            #1;
            if (group_busy_o !== 13'b0 || hemisphere_busy_o ||
                group_fault_valid_o !== 13'b0 ||
                hemisphere_fault_valid_o || producer_valid_o !== 416'b0 ||
                boundary_consume_o !== 3584'b0) begin
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
        input direction;
        input [4:0] stream_index;
        input [255:0] segments;
        integer group_id;
        integer input_boundary;
        integer local_cycle;
        integer issue;
        reg [103:0] local_valid;
        reg [3327:0] local_commands;
        begin
            group_id = slice_id / 4;
            input_boundary = direction ? group_id + 1 : group_id;
            set_boundary_selector(input_boundary, direction, stream_index,
                                  4'b1111, segments);
            issue = issue_id(slice_id, bank_id);
            local_commands = 3328'b0;
            local_commands[issue*32 +: 32] =
                make_cmd(OPCODE_WRITE, direction, stream_index, row, 1'b0);
            for (local_cycle = 0; local_cycle < 4;
                 local_cycle = local_cycle + 1) begin
                local_valid = 104'b0;
                if (local_cycle == 0)
                    local_valid[issue] = 1'b1;
                apply_cycle(local_valid, local_commands);
            end
        end
    endtask

    task check_readback;
        input integer slice_id;
        input integer bank_id;
        input [14:0] row;
        input direction;
        input [4:0] stream_index;
        input [255:0] expected;
        input [8*48-1:0] test_name;
        integer group_id;
        integer output_boundary;
        integer issue;
        integer producer;
        integer local_tile;
        reg [103:0] local_valid;
        reg [3327:0] local_commands;
        begin
            group_id = slice_id / 4;
            output_boundary = direction ? group_id : group_id + 1;
            issue = issue_id(slice_id, bank_id);
            local_commands = 3328'b0;
            local_commands[issue*32 +: 32] =
                make_cmd(OPCODE_READ, direction, stream_index, row, 1'b0);
            for (local_tile = 0; local_tile < 4;
                 local_tile = local_tile + 1) begin
                local_valid = 104'b0;
                if (local_tile == 0)
                    local_valid[issue] = 1'b1;
                apply_cycle(local_valid, local_commands);
                producer = producer_id(slice_id, bank_id, local_tile);
                if (!producer_valid_o[producer] ||
                    producer_boundary_o[producer*4 +: 4] !== output_boundary ||
                    producer_data_o[producer*64 +: 64] !==
                        expected[local_tile*64 +: 64] ||
                    producer_stream_idx_o[producer*5 +: 5] !== stream_index) begin
                    $display("ERROR %0s tile%0d producer mismatch",
                             test_name, local_tile);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b1;
        bank_issue_valid_i = 104'b0;
        bank_issue_i = 3328'b0;
        external_producer_collision_i = 5824'b0;
        clear_boundary_state();
        data0 = pack_segments(64'h100, 64'h101, 64'h102, 64'h103);
        data1 = pack_segments(64'h200, 64'h201, 64'h202, 64'h203);
        data2 = pack_segments(64'h300, 64'h301, 64'h302, 64'h303);

        if (dut.P_MEM_GROUPS == 13 && dut.P_MEM_BOUNDARY_COUNT == 14 &&
            52*2 == 104 && 52*2*4 == 416) begin
            $display("MEM_HEMISPHERE_TOPOLOGY PASS");
        end else begin
            $display("ERROR topology derivation mismatch");
            errors = errors + 1;
        end
        if (52*2 == 104)
            $display("MEM_HEMISPHERE_DEFAULT_CAPACITY_104_MIB PASS");

        $display("RUN_TEST topology_coordinate_mapping");
        reset_dut();
        set_boundary_selector(0, 1'b0, 5'd1, 4'b1111, data0);
        set_boundary_selector(6, 1'b0, 5'd2, 4'b1111, data1);
        set_boundary_selector(12, 1'b0, 5'd3, 4'b1111, data2);
        valids = 104'b0;
        commands = 3328'b0;
        valids[issue_id(0,0)] = 1'b1;
        valids[issue_id(24,0)] = 1'b1;
        valids[issue_id(48,0)] = 1'b1;
        commands[issue_id(0,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE, 1'b0, 5'd1, 15'd1, 1'b0);
        commands[issue_id(24,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE, 1'b0, 5'd2, 15'd2, 1'b0);
        commands[issue_id(48,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE, 1'b0, 5'd3, 15'd3, 1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 104'b0, commands);
            if (!boundary_consume_o[boundary_cell(0,1'b0,5'd1,tile)] ||
                !boundary_consume_o[boundary_cell(6,1'b0,5'd2,tile)] ||
                !boundary_consume_o[boundary_cell(12,1'b0,5'd3,tile)]) begin
                $display("ERROR representative coordinate tile%0d", tile);
                errors = errors + 1;
            end
        end
        check_readback(0,0,15'd1,1'b0,5'd16,data0,"group0_coordinate");
        check_readback(24,0,15'd2,1'b0,5'd17,data1,"group6_coordinate");
        check_readback(48,0,15'd3,1'b0,5'd18,data2,"group12_coordinate");

        $display("RUN_TEST boundary_endpoints");
        reset_dut();
        set_boundary_selector(0,1'b0,5'd4,4'b1111,data0);
        set_boundary_selector(1,1'b0,5'd4,4'b1111,data1);
        setup_write(0,0,15'd4,1'b0,5'd4,data0);
        set_boundary_selector(12,1'b1,5'd5,4'b1111,data0);
        set_boundary_selector(13,1'b1,5'd5,4'b1111,data2);
        setup_write(51,1,15'd5,1'b1,5'd5,data2);
        check_readback(0,0,15'd4,1'b1,5'd19,data0,"boundary0_owner");
        check_readback(51,1,15'd5,1'b0,5'd20,data2,"boundary13_owner");

        $display("RUN_TEST representative_east_mapping");
        reset_dut();
        setup_write(1,0,15'd6,1'b0,5'd6,data0);
        setup_write(25,0,15'd7,1'b0,5'd7,data1);
        setup_write(49,0,15'd8,1'b0,5'd8,data2);
        check_readback(1,0,15'd6,1'b0,5'd21,data0,"east_group0");
        check_readback(25,0,15'd7,1'b0,5'd22,data1,"east_group6");
        check_readback(49,0,15'd8,1'b0,5'd23,data2,"east_group12");

        $display("RUN_TEST representative_west_mapping");
        reset_dut();
        setup_write(2,0,15'd9,1'b1,5'd9,data0);
        setup_write(26,0,15'd10,1'b1,5'd10,data1);
        setup_write(50,0,15'd11,1'b1,5'd11,data2);
        check_readback(2,0,15'd9,1'b1,5'd24,data0,"west_group0");
        check_readback(26,0,15'd10,1'b1,5'd25,data1,"west_group6");
        check_readback(50,0,15'd11,1'b1,5'd26,data2,"west_group12");

        $display("RUN_TEST shared_middle_boundary");
        reset_dut();
        setup_write(20,0,15'd12,1'b0,5'd1,data0);
        setup_write(24,0,15'd13,1'b1,5'd2,data1);
        set_boundary_selector(6,1'b1,5'd3,4'b1111,data2);
        set_boundary_selector(6,1'b0,5'd4,4'b1111,data2);
        valids = 104'b0;
        commands = 3328'b0;
        valids[issue_id(20,0)] = 1'b1;
        valids[issue_id(24,0)] = 1'b1;
        valids[issue_id(21,0)] = 1'b1;
        valids[issue_id(25,0)] = 1'b1;
        commands[issue_id(20,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b0,5'd27,15'd12,1'b0);
        commands[issue_id(24,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b1,5'd28,15'd13,1'b0);
        commands[issue_id(21,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b1,5'd3,15'd14,1'b0);
        commands[issue_id(25,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b0,5'd4,15'd14,1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 104'b0, commands);
            if (producer_boundary_o[producer_id(20,0,tile)*4 +: 4] !== 4'd6 ||
                producer_boundary_o[producer_id(24,0,tile)*4 +: 4] !== 4'd6 ||
                producer_stream_dir_o[producer_id(20,0,tile)] !== 1'b0 ||
                producer_stream_dir_o[producer_id(24,0,tile)] !== 1'b1 ||
                !boundary_consume_o[boundary_cell(6,1'b1,5'd3,tile)] ||
                !boundary_consume_o[boundary_cell(6,1'b0,5'd4,tile)] ||
                internal_mem_collision_o !== 416'b0) begin
                $display("ERROR shared boundary direction tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST distant_group_independence");
        reset_dut();
        set_boundary_selector(0,1'b0,5'd5,4'b1111,data0);
        set_boundary_selector(13,1'b1,5'd6,4'b1111,data2);
        valids = 104'b0;
        commands = 3328'b0;
        valids[issue_id(0,0)] = 1'b1;
        valids[issue_id(51,1)] = 1'b1;
        commands[issue_id(0,0)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b0,5'd5,15'd1,1'b0);
        commands[issue_id(51,1)*32 +: 32] =
            make_cmd(OPCODE_WRITE,1'b1,5'd6,15'd2,1'b0);
        for (tile = 0; tile < 4; tile = tile + 1) begin
            apply_cycle(tile == 0 ? valids : 104'b0, commands);
            if (group_busy_o !== (tile == 3 ? 13'b0 : 13'b1000000000001) ||
                hemisphere_fault_valid_o) begin
                $display("ERROR distant group busy/fault tile%0d", tile);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST external_collision_routing");
        reset_dut();
        // Reuse stored rows at owners producing to boundary0, boundary6, b13.
        valids = 104'b0;
        commands = 3328'b0;
        valids[issue_id(2,0)] = 1'b1;
        valids[issue_id(20,0)] = 1'b1;
        valids[issue_id(49,0)] = 1'b1;
        commands[issue_id(2,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b1,5'd20,15'd9,1'b0);
        commands[issue_id(20,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b0,5'd21,15'd12,1'b0);
        commands[issue_id(49,0)*32 +: 32] =
            make_cmd(OPCODE_READ,1'b0,5'd22,15'd8,1'b0);
        external_producer_collision_i[
            0*416 + producer_id(2,0,0)] = 1'b1;
        external_producer_collision_i[
            6*416 + producer_id(20,0,0)] = 1'b1;
        external_producer_collision_i[
            13*416 + producer_id(49,0,0)] = 1'b1;
        apply_cycle(valids, commands);
        if (bank_fault_code_o[issue_id(2,0)*3 +: 3] !== FAULT_COLLISION ||
            bank_fault_code_o[issue_id(20,0)*3 +: 3] !== FAULT_COLLISION ||
            bank_fault_code_o[issue_id(49,0)*3 +: 3] !== FAULT_COLLISION ||
            bank_fault_valid_o !==
                ((104'b1 << issue_id(2,0)) |
                 (104'b1 << issue_id(20,0)) |
                 (104'b1 << issue_id(49,0)))) begin
            $display("ERROR external collision owner routing");
            errors = errors + 1;
        end
        external_producer_collision_i = 5824'b0;

        $display("RUN_TEST continuous_multi_group_traffic");
        reset_dut();
        // Prepare Read sources in group0 and group12.
        setup_write(0,0,15'd0,1'b0,5'd1,data0);
        setup_write(48,0,15'd0,1'b1,5'd2,data2);
        for (local_index = 0; local_index < 8; local_index = local_index + 1) begin
            set_boundary_selector(6,1'b0,local_index[4:0],4'b1111,data1);
            set_boundary_selector(7,1'b1,(local_index+8),4'b1111,data1);
        end
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            valids = 104'b0;
            commands = 3328'b0;
            valids[issue_id(0,0)] = 1'b1;
            valids[issue_id(24,0)] = 1'b1;
            valids[issue_id(24,1)] = 1'b1;
            valids[issue_id(48,0)] = 1'b1;
            commands[issue_id(0,0)*32 +: 32] =
                make_cmd(OPCODE_READ,1'b0,5'd20+cycle,15'd0,1'b0);
            commands[issue_id(24,0)*32 +: 32] =
                make_cmd(OPCODE_WRITE,1'b0,cycle[4:0],15'd4+cycle,1'b0);
            commands[issue_id(24,1)*32 +: 32] =
                make_cmd(OPCODE_WRITE,1'b1,(cycle+8),15'd8+cycle,1'b1);
            commands[issue_id(48,0)*32 +: 32] =
                make_cmd(OPCODE_READ,1'b1,5'd24+cycle,15'd0,1'b0);
            apply_cycle(valids, commands);
            if (cycle == 3) begin
                if (count_producers() != 8 ||
                    count_boundary_consume(6) != 4 ||
                    group_busy_o !== 13'b1000001000001 ||
                    internal_mem_collision_o !== 416'b0 ||
                    hemisphere_fault_valid_o) begin
                    $display("ERROR continuous multi-group steady-state");
                    errors = errors + 1;
                end
            end
        end
        for (cycle = 0; cycle < 3; cycle = cycle + 1) begin
            idle_cycle();
            if (count_producers() != (3-cycle)*2 ||
                count_boundary_consume(6) != (3-cycle) ||
                hemisphere_fault_valid_o) begin
                $display("ERROR continuous multi-group drain cycle%0d", cycle);
                errors = errors + 1;
            end
        end
        rst_ni = 1'b0;
        #1;
        if (hemisphere_busy_o || hemisphere_fault_valid_o ||
            producer_valid_o !== 416'b0) begin
            $display("ERROR hemisphere reset transient state");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
