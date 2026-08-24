#include "mem_group_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

constexpr std::uint8_t kRead = 0;
constexpr std::uint8_t kWrite = 1;
using Segments = std::array<std::uint64_t, MemGroupModel::TILES>;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << message << '\n';
        ++failures;
    }
}

std::uint32_t make_command(const std::uint8_t opcode,
                           const bool direction,
                           const std::uint8_t stream,
                           const std::uint16_t row,
                           const bool preserve = false) {
    return (static_cast<std::uint32_t>(preserve) << 31U) |
           ((static_cast<std::uint32_t>(row) & 0x7FFFU) << 15U) |
           ((static_cast<std::uint32_t>(direction) << 8U)) |
           ((static_cast<std::uint32_t>(stream) & 0x1FU) << 3U) |
           (static_cast<std::uint32_t>(opcode) & 0x7U);
}

void set_selector(MemGroupModel::Inputs& inputs,
                  const bool use_left,
                  const bool direction,
                  const std::uint8_t stream,
                  const std::array<bool, 4>& valid,
                  const Segments& data) {
    auto& boundary = use_left ? inputs.left_boundary_state
                              : inputs.right_boundary_state;
    const std::size_t dir = direction ? 1U : 0U;
    for (std::size_t tile = 0; tile < 4; ++tile) {
        boundary[dir][stream][tile].valid = valid[tile];
        boundary[dir][stream][tile].data = data[tile];
    }
}

MemGroupModel::Outputs run_cycle(MemGroupModel& model,
                                 MemGroupModel::Inputs& inputs,
                                 const MemGroupModel::IssueValid& valid,
                                 const MemGroupModel::IssueRaw& raw) {
    inputs.issue_valid = valid;
    inputs.issue_raw = raw;
    return model.step(inputs);
}

MemGroupModel::Outputs idle_cycle(MemGroupModel& model,
                                  MemGroupModel::Inputs& inputs) {
    return run_cycle(model, inputs, {}, {});
}

std::size_t consume_count(
    const MemSliceModel::ConsumeDirectionState& consume) {
    std::size_t count = 0;
    for (const auto& direction : consume) {
        for (const auto& stream : direction) {
            for (const bool value : stream) {
                count += value ? 1U : 0U;
            }
        }
    }
    return count;
}

std::size_t producer_count(const MemGroupModel::Producers& producers) {
    std::size_t count = 0;
    for (const auto& slice : producers) {
        for (const auto& bank : slice) {
            for (const auto& producer : bank) {
                count += producer.valid ? 1U : 0U;
            }
        }
    }
    return count;
}

std::size_t collision_count(
    const MemGroupModel::CollisionFeedback& collision) {
    std::size_t count = 0;
    for (const auto& slice : collision) {
        for (const auto& bank : slice) {
            for (const bool value : bank) {
                count += value ? 1U : 0U;
            }
        }
    }
    return count;
}

void write_row(MemGroupModel& model,
               MemGroupModel::Inputs& inputs,
               const std::size_t slice,
               const std::size_t bank,
               const std::uint16_t row,
               const bool direction,
               const std::uint8_t stream,
               const Segments& data) {
    const std::array<bool, 4> all_valid{true, true, true, true};
    set_selector(inputs, !direction, direction, stream, all_valid, data);
    MemGroupModel::IssueRaw raw{};
    raw[slice][bank] = make_command(kWrite, direction, stream, row);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        MemGroupModel::IssueValid valid{};
        valid[slice][bank] = tile == 0U;
        run_cycle(model, inputs, valid, raw);
    }
}

void check_read_row(MemGroupModel& model,
                    MemGroupModel::Inputs& inputs,
                    const std::size_t slice,
                    const std::size_t bank,
                    const std::uint16_t row,
                    const bool direction,
                    const std::uint8_t stream,
                    const Segments& expected,
                    const std::string& name) {
    MemGroupModel::IssueRaw raw{};
    raw[slice][bank] = make_command(kRead, direction, stream, row);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        MemGroupModel::IssueValid valid{};
        valid[slice][bank] = tile == 0U;
        const auto outputs = run_cycle(model, inputs, valid, raw);
        const auto& producer = direction
            ? outputs.left_producer[slice][bank][tile]
            : outputs.right_producer[slice][bank][tile];
        expect(producer.valid && producer.data == expected[tile] &&
                   producer.stream_dir == direction &&
                   producer.stream_idx == stream,
               name + " producer mismatch");
    }
}

void test_east_west_boundary_mapping() {
    std::cout << "RUN_TEST east_west_boundary_mapping" << '\n';
    MemGroupModel model;
    MemGroupModel::Inputs inputs{};
    const Segments left_data{0x10, 0x11, 0x12, 0x13};
    const Segments right_data{0x20, 0x21, 0x22, 0x23};
    const Segments wrong{0xF0, 0xF1, 0xF2, 0xF3};
    const std::array<bool, 4> all_valid{true, true, true, true};

    set_selector(inputs, false, false, 1, all_valid, wrong);
    write_row(model, inputs, 0, 0, 100, false, 1, left_data);
    set_selector(inputs, true, true, 2, all_valid, wrong);
    write_row(model, inputs, 1, 0, 101, true, 2, right_data);
    check_read_row(model, inputs, 0, 0, 100, false, 10, left_data,
                   "East left-to-right");
    check_read_row(model, inputs, 1, 0, 101, true, 11, right_data,
                   "West right-to-left");
}

void test_four_slice_independence() {
    std::cout << "RUN_TEST four_slice_independence" << '\n';
    MemGroupModel model;
    MemGroupModel::Inputs inputs{};
    const std::array<bool, 4> all_valid{true, true, true, true};
    std::array<Segments, 4> data{};
    MemGroupModel::IssueRaw raw{};
    MemGroupModel::IssueValid valid{};

    for (std::size_t slice = 0; slice < 4; ++slice) {
        for (std::size_t tile = 0; tile < 4; ++tile) {
            data[slice][tile] = 0x1000U + slice*0x100U + tile;
        }
        set_selector(inputs, true, false,
                     static_cast<std::uint8_t>(slice), all_valid, data[slice]);
        valid[slice][0] = true;
        raw[slice][0] = make_command(kWrite, false,
            static_cast<std::uint8_t>(slice),
            static_cast<std::uint16_t>(200U + slice));
    }
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs,
                                       tile == 0U ? valid
                                                  : MemGroupModel::IssueValid{},
                                       raw);
        expect(consume_count(outputs.left_consume) == 4U,
               "four-slice independent consume mismatch");
        if (tile < 3U) {
            expect(outputs.group_busy, "four-slice busy dropped early");
        }
    }
    for (std::size_t slice = 0; slice < 4; ++slice) {
        check_read_row(model, inputs, slice, 0,
                       static_cast<std::uint16_t>(200U + slice), false,
                       static_cast<std::uint8_t>(16U + slice), data[slice],
                       "four-slice independent SRAM");
    }
}

void test_broadcast_consume() {
    std::cout << "RUN_TEST broadcast_consume" << '\n';
    MemGroupModel model;
    MemGroupModel::Inputs inputs{};
    const Segments data{0x30, 0x31, 0x32, 0x33};
    const std::array<bool, 4> all_valid{true, true, true, true};
    set_selector(inputs, true, false, 5, all_valid, data);
    MemGroupModel::IssueRaw raw{};
    MemGroupModel::IssueValid valid{};
    for (std::size_t slice = 0; slice < 4; ++slice) {
        for (std::size_t bank = 0; bank < 2; ++bank) {
            valid[slice][bank] = true;
            raw[slice][bank] = make_command(kWrite, false, 5,
                static_cast<std::uint16_t>(300U + slice*2U + bank));
        }
    }
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs,
                                       tile == 0U ? valid
                                                  : MemGroupModel::IssueValid{},
                                       raw);
        expect(outputs.left_consume[0][5][tile] &&
                   consume_count(outputs.left_consume) == 1U &&
                   collision_count(outputs.internal_collision) == 0U &&
                   !outputs.group_fault_valid,
               "broadcast consume aggregation mismatch");
        for (std::size_t slice = 0; slice < 4; ++slice) {
            for (std::size_t bank = 0; bank < 2; ++bank) {
                expect(outputs.slice[slice].consume[bank][0][5][tile],
                       "broadcast consumer identity lost");
            }
        }
    }
}

void test_nonconflicting_parallel_read() {
    std::cout << "RUN_TEST nonconflicting_parallel_read" << '\n';
    MemGroupModel model;
    MemGroupModel::Inputs inputs{};
    const Segments data{0x40, 0x41, 0x42, 0x43};
    for (std::size_t slice = 0; slice < 4; ++slice) {
        write_row(model, inputs, slice, 0,
                  static_cast<std::uint16_t>(400U + slice), false,
                  static_cast<std::uint8_t>(slice), data);
    }
    MemGroupModel::IssueRaw raw{};
    MemGroupModel::IssueValid valid{};
    for (std::size_t slice = 0; slice < 4; ++slice) {
        const bool direction = (slice & 1U) != 0U;
        valid[slice][0] = true;
        raw[slice][0] = make_command(kRead, direction,
            static_cast<std::uint8_t>(12U + slice),
            static_cast<std::uint16_t>(400U + slice));
    }
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs,
                                       tile == 0U ? valid
                                                  : MemGroupModel::IssueValid{},
                                       raw);
        expect(producer_count(outputs.left_producer) == 2U &&
                   producer_count(outputs.right_producer) == 2U &&
                   collision_count(outputs.internal_collision) == 0U &&
                   !outputs.group_fault_valid,
               "parallel non-conflicting Read mismatch");
    }
}

void test_intra_group_producer_collision() {
    std::cout << "RUN_TEST intra_group_producer_collision" << '\n';
    MemGroupModel model;
    MemGroupModel::Inputs inputs{};
    const Segments data0{0x50, 0x51, 0x52, 0x53};
    const Segments data1{0x60, 0x61, 0x62, 0x63};
    write_row(model, inputs, 0, 0, 500, false, 1, data0);
    write_row(model, inputs, 2, 1, 501, false, 2, data1);
    MemGroupModel::IssueRaw raw{};
    raw[0][0] = make_command(kRead, false, 20, 500);
    raw[2][1] = make_command(kRead, false, 20, 501);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        MemGroupModel::IssueValid valid{};
        valid[0][0] = tile == 0U;
        valid[2][1] = tile == 0U;
        const auto outputs = run_cycle(model, inputs, valid, raw);
        expect(outputs.internal_collision[0][0][tile] &&
                   outputs.internal_collision[2][1][tile] &&
                   outputs.right_producer[0][0][tile].valid &&
                   outputs.right_producer[2][1][tile].valid &&
                   outputs.slice[0].fault[0].code ==
                       MemSliceModel::FaultCode::COLLISION &&
                   outputs.slice[2].fault[1].code ==
                       MemSliceModel::FaultCode::COLLISION,
               "intra-group collision or no-winner semantics mismatch");
    }

    // External feedback shares the same candidate identity and fault path.
    model.reset();
    inputs.external_collision[0][0][0] = true;
    MemGroupModel::IssueValid valid{};
    valid[0][0] = true;
    MemGroupModel::IssueRaw external_raw{};
    external_raw[0][0] = make_command(kRead, true, 21, 500);
    const auto outputs = run_cycle(model, inputs, valid, external_raw);
    expect(outputs.left_producer[0][0][0].valid &&
               outputs.slice[0].fault[0].code ==
                   MemSliceModel::FaultCode::COLLISION,
           "external collision feedback mismatch");
}

void test_continuous_mixed_traffic() {
    std::cout << "RUN_TEST continuous_mixed_traffic" << '\n';
    MemGroupModel model;
    MemGroupModel::Inputs inputs{};
    const Segments read0{0x70, 0x71, 0x72, 0x73};
    const Segments read1{0x80, 0x81, 0x82, 0x83};
    const Segments write_data{0x90, 0x91, 0x92, 0x93};
    write_row(model, inputs, 0, 0, 600, false, 1, read0);
    write_row(model, inputs, 0, 1, 601, true, 2, read1);
    const std::array<bool, 4> all_valid{true, true, true, true};
    for (std::size_t stream = 0; stream < 16; ++stream) {
        set_selector(inputs, stream < 4U || (stream >= 8U && stream < 12U),
                     stream >= 4U && stream < 8U || stream >= 12U,
                     static_cast<std::uint8_t>(stream), all_valid,
                     write_data);
    }

    for (std::size_t cycle = 0; cycle < 4; ++cycle) {
        MemGroupModel::IssueValid valid{};
        MemGroupModel::IssueRaw raw{};
        // slice0 Read, slice1 Write, slice2 WriteTap, slice3 bubble.
        valid[0] = {true, true};
        valid[1] = {true, true};
        valid[2] = {true, true};
        raw[0][0] = make_command(kRead, false,
            static_cast<std::uint8_t>(20U + cycle), 600);
        raw[0][1] = make_command(kRead, true,
            static_cast<std::uint8_t>(24U + cycle), 601);
        raw[1][0] = make_command(kWrite, false,
            static_cast<std::uint8_t>(cycle),
            static_cast<std::uint16_t>(610U + cycle));
        raw[1][1] = make_command(kWrite, true,
            static_cast<std::uint8_t>(cycle + 4U),
            static_cast<std::uint16_t>(620U + cycle));
        raw[2][0] = make_command(kWrite, false,
            static_cast<std::uint8_t>(cycle + 8U),
            static_cast<std::uint16_t>(630U + cycle), true);
        raw[2][1] = make_command(kWrite, true,
            static_cast<std::uint8_t>(cycle + 12U),
            static_cast<std::uint16_t>(640U + cycle), true);
        const auto outputs = run_cycle(model, inputs, valid, raw);
        if (cycle == 3U) {
            expect(producer_count(outputs.left_producer) == 4U &&
                       producer_count(outputs.right_producer) == 4U &&
                       consume_count(outputs.left_consume) == 4U &&
                       consume_count(outputs.right_consume) == 4U &&
                       collision_count(outputs.internal_collision) == 0U &&
                       !outputs.group_fault_valid &&
                       outputs.slice_busy ==
                           std::array<bool, 4>{true, true, true, false},
                   "continuous mixed steady-state mismatch");
        }
    }
    for (std::size_t cycle = 0; cycle < 3; ++cycle) {
        const auto outputs = idle_cycle(model, inputs);
        const std::size_t expected = 3U - cycle;
        expect(producer_count(outputs.left_producer) == expected &&
                   producer_count(outputs.right_producer) == expected &&
                   consume_count(outputs.left_consume) == expected &&
                   consume_count(outputs.right_consume) == expected &&
                   collision_count(outputs.internal_collision) == 0U &&
                   !outputs.group_fault_valid,
               "continuous mixed drain mismatch");
    }
    model.reset();
    const auto outputs = idle_cycle(model, inputs);
    expect(!outputs.group_busy && !outputs.group_fault_valid &&
               producer_count(outputs.left_producer) == 0U &&
               producer_count(outputs.right_producer) == 0U,
           "Group reset transient-state mismatch");
}

}  // namespace

int main() {
    test_east_west_boundary_mapping();
    test_four_slice_independence();
    test_broadcast_consume();
    test_nonconflicting_parallel_read();
    test_intra_group_producer_collision();
    test_continuous_mixed_traffic();

    if (failures == 0) {
        std::cout << "CMODEL_MEM_GROUP TEST_PASS" << '\n';
        return 0;
    }
    std::cout << "CMODEL_MEM_GROUP TEST_FAIL failures="
              << failures << '\n';
    return 1;
}
