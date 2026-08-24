`timescale 1ns/1ps

// Full MEM hierarchy container. West and East hemispheres retain independent
// issue, SRAM/control state, local boundary coordinates, and observations.
// This wrapper does not implement SR propagation, routing, or arbitration.
module mem_full #(
    parameter P_MEM_SLICES_PER_HEMI   = 52,
    parameter P_MEM_SLICES_PER_GROUP  = 4,
    parameter P_MEM_BANK_DEPTH_ROWS   = 32768,
    parameter P_SLICE_FAULT_CODE_BITS = 3
) (
    input  wire clk_i,
    input  wire west_rst_ni,
    input  wire east_rst_ni,

    input  wire [P_MEM_SLICES_PER_HEMI*2-1:0]
        west_bank_issue_valid_i,
    input  wire [P_MEM_SLICES_PER_HEMI*2*32-1:0]
        west_bank_issue_i,
    input  wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*256-1:0]
        west_mem_boundary_state_valid_i,
    input  wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*16384-1:0]
        west_mem_boundary_state_data_i,
    input  wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*
                 P_MEM_SLICES_PER_HEMI*8-1:0]
        west_external_producer_collision_i,

    output wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*256-1:0]
        west_mem_boundary_consume_o,
    output wire [P_MEM_SLICES_PER_HEMI*8-1:0]
        west_producer_valid_o,
    output wire [P_MEM_SLICES_PER_HEMI*8*64-1:0]
        west_producer_data_o,
    output wire [P_MEM_SLICES_PER_HEMI*8-1:0]
        west_producer_stream_dir_o,
    output wire [P_MEM_SLICES_PER_HEMI*8*5-1:0]
        west_producer_stream_idx_o,
    output wire [P_MEM_SLICES_PER_HEMI*8*4-1:0]
        west_producer_boundary_o,
    output wire [P_MEM_SLICES_PER_HEMI*8-1:0]
        west_internal_mem_collision_o,
    output wire [P_MEM_SLICES_PER_HEMI*2-1:0]
        west_bank_fault_valid_o,
    output wire [P_MEM_SLICES_PER_HEMI*2*P_SLICE_FAULT_CODE_BITS-1:0]
        west_bank_fault_code_o,
    output wire [P_MEM_SLICES_PER_HEMI*2-1:0]
        west_bank_fault_tile_valid_o,
    output wire [P_MEM_SLICES_PER_HEMI*2*2-1:0]
        west_bank_fault_tile_id_o,
    output wire [P_MEM_SLICES_PER_HEMI*2*15-1:0]
        west_bank_fault_row_o,
    output wire [(P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)-1:0]
        west_group_fault_valid_o,
    output wire west_hemisphere_fault_valid_o,
    output wire [(P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)-1:0]
        west_group_busy_o,
    output wire west_hemisphere_busy_o,

    input  wire [P_MEM_SLICES_PER_HEMI*2-1:0]
        east_bank_issue_valid_i,
    input  wire [P_MEM_SLICES_PER_HEMI*2*32-1:0]
        east_bank_issue_i,
    input  wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*256-1:0]
        east_mem_boundary_state_valid_i,
    input  wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*16384-1:0]
        east_mem_boundary_state_data_i,
    input  wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*
                 P_MEM_SLICES_PER_HEMI*8-1:0]
        east_external_producer_collision_i,

    output wire [((P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)+1)*256-1:0]
        east_mem_boundary_consume_o,
    output wire [P_MEM_SLICES_PER_HEMI*8-1:0]
        east_producer_valid_o,
    output wire [P_MEM_SLICES_PER_HEMI*8*64-1:0]
        east_producer_data_o,
    output wire [P_MEM_SLICES_PER_HEMI*8-1:0]
        east_producer_stream_dir_o,
    output wire [P_MEM_SLICES_PER_HEMI*8*5-1:0]
        east_producer_stream_idx_o,
    output wire [P_MEM_SLICES_PER_HEMI*8*4-1:0]
        east_producer_boundary_o,
    output wire [P_MEM_SLICES_PER_HEMI*8-1:0]
        east_internal_mem_collision_o,
    output wire [P_MEM_SLICES_PER_HEMI*2-1:0]
        east_bank_fault_valid_o,
    output wire [P_MEM_SLICES_PER_HEMI*2*P_SLICE_FAULT_CODE_BITS-1:0]
        east_bank_fault_code_o,
    output wire [P_MEM_SLICES_PER_HEMI*2-1:0]
        east_bank_fault_tile_valid_o,
    output wire [P_MEM_SLICES_PER_HEMI*2*2-1:0]
        east_bank_fault_tile_id_o,
    output wire [P_MEM_SLICES_PER_HEMI*2*15-1:0]
        east_bank_fault_row_o,
    output wire [(P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)-1:0]
        east_group_fault_valid_o,
    output wire east_hemisphere_fault_valid_o,
    output wire [(P_MEM_SLICES_PER_HEMI/P_MEM_SLICES_PER_GROUP)-1:0]
        east_group_busy_o,
    output wire east_hemisphere_busy_o
);

    // A single public parameter set is the strongest consistency guarantee:
    // it is impossible to configure West and East with different capacities.
    localparam P_WEST_SLICES_PER_HEMI  = P_MEM_SLICES_PER_HEMI;
    localparam P_EAST_SLICES_PER_HEMI  = P_MEM_SLICES_PER_HEMI;
    localparam P_WEST_SLICES_PER_GROUP = P_MEM_SLICES_PER_GROUP;
    localparam P_EAST_SLICES_PER_GROUP = P_MEM_SLICES_PER_GROUP;
    localparam P_WEST_BANK_DEPTH_ROWS  = P_MEM_BANK_DEPTH_ROWS;
    localparam P_EAST_BANK_DEPTH_ROWS  = P_MEM_BANK_DEPTH_ROWS;

`ifndef SYNTHESIS
    initial begin
        if (P_WEST_SLICES_PER_HEMI != P_EAST_SLICES_PER_HEMI ||
            P_WEST_SLICES_PER_GROUP != P_EAST_SLICES_PER_GROUP ||
            P_WEST_BANK_DEPTH_ROWS != P_EAST_BANK_DEPTH_ROWS) begin
            $display("ERROR mem_full West/East parameter mismatch");
            $finish;
        end
        if (P_MEM_SLICES_PER_HEMI <= 0 ||
            P_MEM_SLICES_PER_GROUP <= 0 ||
            (P_MEM_SLICES_PER_HEMI % P_MEM_SLICES_PER_GROUP) != 0 ||
            P_MEM_SLICES_PER_GROUP != 4 ||
            P_MEM_BANK_DEPTH_ROWS <= 0) begin
            $display("ERROR mem_full invalid shared MEM parameters");
            $finish;
        end
    end
`endif

    mem_hemisphere #(
        .P_MEM_SLICES_PER_HEMI(P_WEST_SLICES_PER_HEMI),
        .P_MEM_SLICES_PER_GROUP(P_WEST_SLICES_PER_GROUP),
        .P_MEM_BANK_DEPTH_ROWS(P_WEST_BANK_DEPTH_ROWS),
        .P_SLICE_FAULT_CODE_BITS(P_SLICE_FAULT_CODE_BITS)
    ) u_west_mem_hemisphere (
        .clk_i(clk_i),
        .rst_ni(west_rst_ni),
        .bank_issue_valid_i(west_bank_issue_valid_i),
        .bank_issue_i(west_bank_issue_i),
        .boundary_state_valid_i(west_mem_boundary_state_valid_i),
        .boundary_state_data_i(west_mem_boundary_state_data_i),
        .external_producer_collision_i(
            west_external_producer_collision_i),
        .boundary_consume_o(west_mem_boundary_consume_o),
        .producer_valid_o(west_producer_valid_o),
        .producer_data_o(west_producer_data_o),
        .producer_stream_dir_o(west_producer_stream_dir_o),
        .producer_stream_idx_o(west_producer_stream_idx_o),
        .producer_boundary_o(west_producer_boundary_o),
        .internal_mem_collision_o(west_internal_mem_collision_o),
        .bank_fault_valid_o(west_bank_fault_valid_o),
        .bank_fault_code_o(west_bank_fault_code_o),
        .bank_fault_tile_valid_o(west_bank_fault_tile_valid_o),
        .bank_fault_tile_id_o(west_bank_fault_tile_id_o),
        .bank_fault_row_o(west_bank_fault_row_o),
        .group_fault_valid_o(west_group_fault_valid_o),
        .hemisphere_fault_valid_o(west_hemisphere_fault_valid_o),
        .group_busy_o(west_group_busy_o),
        .hemisphere_busy_o(west_hemisphere_busy_o)
    );

    mem_hemisphere #(
        .P_MEM_SLICES_PER_HEMI(P_EAST_SLICES_PER_HEMI),
        .P_MEM_SLICES_PER_GROUP(P_EAST_SLICES_PER_GROUP),
        .P_MEM_BANK_DEPTH_ROWS(P_EAST_BANK_DEPTH_ROWS),
        .P_SLICE_FAULT_CODE_BITS(P_SLICE_FAULT_CODE_BITS)
    ) u_east_mem_hemisphere (
        .clk_i(clk_i),
        .rst_ni(east_rst_ni),
        .bank_issue_valid_i(east_bank_issue_valid_i),
        .bank_issue_i(east_bank_issue_i),
        .boundary_state_valid_i(east_mem_boundary_state_valid_i),
        .boundary_state_data_i(east_mem_boundary_state_data_i),
        .external_producer_collision_i(
            east_external_producer_collision_i),
        .boundary_consume_o(east_mem_boundary_consume_o),
        .producer_valid_o(east_producer_valid_o),
        .producer_data_o(east_producer_data_o),
        .producer_stream_dir_o(east_producer_stream_dir_o),
        .producer_stream_idx_o(east_producer_stream_idx_o),
        .producer_boundary_o(east_producer_boundary_o),
        .internal_mem_collision_o(east_internal_mem_collision_o),
        .bank_fault_valid_o(east_bank_fault_valid_o),
        .bank_fault_code_o(east_bank_fault_code_o),
        .bank_fault_tile_valid_o(east_bank_fault_tile_valid_o),
        .bank_fault_tile_id_o(east_bank_fault_tile_id_o),
        .bank_fault_row_o(east_bank_fault_row_o),
        .group_fault_valid_o(east_group_fault_valid_o),
        .hemisphere_fault_valid_o(east_hemisphere_fault_valid_o),
        .group_busy_o(east_group_busy_o),
        .hemisphere_busy_o(east_hemisphere_busy_o)
    );

endmodule
