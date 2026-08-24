#include "mem_slice_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

constexpr std::uint8_t kRead = 0;
constexpr std::uint8_t kWrite = 1;
using Segments = std::array<std::uint64_t, MemSliceModel::TILES>;

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
                           const bool preserve = false,
                           const std::uint8_t map_stream = 0,
                           const bool reserved = false) {
    const std::uint32_t packed_stream =
        (static_cast<std::uint32_t>(direction) << 5U) |
        (static_cast<std::uint32_t>(stream) & 0x1FU);
    return (static_cast<std::uint32_t>(preserve) << 31U) |
           (static_cast<std::uint32_t>(reserved) << 30U) |
           ((static_cast<std::uint32_t>(row) & 0x7FFFU) << 15U) |
           ((static_cast<std::uint32_t>(map_stream) & 0x3FU) << 9U) |
           ((packed_stream & 0x3FU) << 3U) |
           (static_cast<std::uint32_t>(opcode) & 0x7U);
}

void set_selector(MemSliceModel::Inputs& inputs,
                  const bool direction,
                  const std::uint8_t stream,
                  const std::array<bool, MemSliceModel::TILES>& valid,
                  const Segments& data) {
    const std::size_t dir = direction ? 1U : 0U;
    for (std::size_t tile = 0; tile < MemSliceModel::TILES; ++tile) {
        inputs.sr_state[dir][stream][tile].valid = valid[tile];
        inputs.sr_state[dir][stream][tile].data = data[tile];
    }
}

MemSliceModel::Outputs run_cycle(MemSliceModel& model,
                                 MemSliceModel::Inputs& inputs,
                                 const bool valid0,
                                 const std::uint32_t command0,
                                 const bool valid1,
                                 const std::uint32_t command1) {
    inputs.bank_issue_valid = {valid0, valid1};
    inputs.bank_issue_raw = {command0, command1};
    return model.step(inputs);
}

MemSliceModel::Outputs idle_cycle(MemSliceModel& model,
                                  MemSliceModel::Inputs& inputs) {
    return run_cycle(model, inputs, false, 0, false, 0);
}

std::size_t consume_count(const MemSliceModel::Outputs& outputs) {
    std::size_t count = 0;
    for (const auto& bank : outputs.consume) {
        for (const auto& direction : bank) {
            for (const auto& stream : direction) {
                for (const bool consumed : stream) {
                    count += consumed ? 1U : 0U;
                }
            }
        }
    }
    return count;
}

std::size_t injection_count(const MemSliceModel::Outputs& outputs) {
    std::size_t count = 0;
    for (const auto& bank : outputs.injection) {
        for (const auto& injection : bank) {
            count += injection.valid ? 1U : 0U;
        }
    }
    return count;
}

void write_row(MemSliceModel& model,
               MemSliceModel::Inputs& inputs,
               const std::size_t bank,
               const std::uint16_t row,
               const bool direction,
               const std::uint8_t stream,
               const Segments& data) {
    const std::array<bool, 4> all_valid{true, true, true, true};
    set_selector(inputs, direction, stream, all_valid, data);
    const auto command = make_command(kWrite, direction, stream, row);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        if (bank == 0U) {
            run_cycle(model, inputs, tile == 0U, command, false, 0);
        } else {
            run_cycle(model, inputs, false, 0, tile == 0U, command);
        }
    }
}

void check_read_row(MemSliceModel& model,
                    MemSliceModel::Inputs& inputs,
                    const std::size_t bank,
                    const std::uint16_t row,
                    const bool direction,
                    const std::uint8_t stream,
                    const Segments& expected,
                    const std::string& name) {
    const auto command = make_command(kRead, direction, stream, row);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = bank == 0U
            ? run_cycle(model, inputs, tile == 0U, command, false, 0)
            : run_cycle(model, inputs, false, 0, tile == 0U, command);
        const auto& injection = outputs.injection[bank][tile];
        expect(injection_count(outputs) == 1U && injection.valid &&
                   injection.data == expected[tile] &&
                   injection.stream_dir == direction &&
                   injection.stream_idx == stream,
               name + " read injection mismatch");
    }
}

void test_dual_bank_independence_and_parallelism() {
    std::cout << "RUN_TEST dual_bank_independence_and_parallelism" << '\n';
    MemSliceModel model;
    MemSliceModel::Inputs inputs{};
    const std::array<bool, 4> all_valid{true, true, true, true};
    std::array<std::uint32_t, 4> command0{};
    std::array<std::uint32_t, 4> command1{};
    std::array<Segments, 4> data0{};
    std::array<Segments, 4> data1{};

    for (std::size_t wave = 0; wave < 4; ++wave) {
        for (std::size_t tile = 0; tile < 4; ++tile) {
            data0[wave][tile] = 0x1000000000000000ULL |
                                (wave << 8U) | tile;
            data1[wave][tile] = 0x2000000000000000ULL |
                                (wave << 8U) | tile;
        }
        set_selector(inputs, false, static_cast<std::uint8_t>(wave),
                     all_valid, data0[wave]);
        set_selector(inputs, true, static_cast<std::uint8_t>(wave + 8U),
                     all_valid, data1[wave]);
        command0[wave] = make_command(kWrite, false,
            static_cast<std::uint8_t>(wave),
            static_cast<std::uint16_t>(2000U + wave));
        command1[wave] = make_command(kWrite, true,
            static_cast<std::uint8_t>(wave + 8U),
            static_cast<std::uint16_t>(2100U + wave));
    }

    for (std::size_t cycle = 0; cycle < 4; ++cycle) {
        const auto outputs = run_cycle(model, inputs, true, command0[cycle],
                                       true, command1[cycle]);
        expect(outputs.bank_busy[0] && outputs.bank_busy[1] &&
                   outputs.slice_busy,
               "dual-bank busy independence mismatch");
        expect(consume_count(outputs) == (cycle + 1U)*2U,
               "dual-bank II=1 fill mismatch");
        if (cycle == 3U) {
            expect(outputs.north_cmd_valid[0] &&
                       outputs.north_cmd_valid[1] &&
                       outputs.north_cmd[0] == command0[0] &&
                       outputs.north_cmd[1] == command1[0],
                   "dual-bank first north command mismatch");
        }
    }
    for (std::size_t cycle = 0; cycle < 3; ++cycle) {
        const auto outputs = idle_cycle(model, inputs);
        expect(consume_count(outputs) == (3U - cycle)*2U,
               "dual-bank II=1 drain mismatch");
        expect(outputs.north_cmd[0] == command0[cycle + 1U] &&
                   outputs.north_cmd[1] == command1[cycle + 1U],
               "dual-bank north order mismatch");
    }

    check_read_row(model, inputs, 0, 2000, false, 20, data0[0],
                   "bank0 independent row");
    check_read_row(model, inputs, 1, 2100, true, 21, data1[0],
                   "bank1 independent row");
}

void test_sr_write_selection_and_broadcast_consume() {
    std::cout << "RUN_TEST sr_write_selection_and_broadcast_consume" << '\n';
    MemSliceModel model;
    MemSliceModel::Inputs inputs{};
    const std::array<bool, 4> all_valid{true, true, true, true};
    std::array<std::uint32_t, 4> command{};
    std::array<Segments, 4> selected_data{};

    for (std::size_t wave = 0; wave < 4; ++wave) {
        for (std::size_t tile = 0; tile < 4; ++tile) {
            selected_data[wave][tile] = 0x3000000000000000ULL |
                                        (wave << 8U) | tile;
        }
        const auto stream = static_cast<std::uint8_t>(wave + 4U);
        set_selector(inputs, false, stream, all_valid, selected_data[wave]);
        command[wave] = make_command(kWrite, false, stream,
            static_cast<std::uint16_t>(3000U + wave));
    }
    for (std::size_t cycle = 0; cycle < 4; ++cycle) {
        const auto outputs = run_cycle(model, inputs, true, command[cycle],
                                       false, 0);
        if (cycle == 3U) {
            for (std::size_t tile = 0; tile < 4; ++tile) {
                const std::size_t wave = 3U - tile;
                expect(outputs.consume[0][0][wave + 4U][tile],
                       "per-tile SR selector mismatch");
            }
        }
    }
    for (std::size_t cycle = 0; cycle < 3; ++cycle) {
        idle_cycle(model, inputs);
    }
    for (std::size_t wave = 0; wave < 4; ++wave) {
        check_read_row(model, inputs, 0,
            static_cast<std::uint16_t>(3000U + wave), false,
            static_cast<std::uint8_t>(16U + wave), selected_data[wave],
            "per-tile selected data");
    }

    const Segments broadcast{0xB0, 0xB1, 0xB2, 0xB3};
    set_selector(inputs, true, 12, all_valid, broadcast);
    const auto write0 = make_command(kWrite, true, 12, 3100);
    const auto write1 = make_command(kWrite, true, 12, 3101);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs, tile == 0U, write0,
                                       tile == 0U, write1);
        expect(outputs.consume[0][1][12][tile] &&
                   outputs.consume[1][1][12][tile] &&
                   consume_count(outputs) == 2U,
               "same-stream broadcast consume mismatch");
    }
    check_read_row(model, inputs, 0, 3100, false, 22, broadcast,
                   "broadcast bank0 data");
    check_read_row(model, inputs, 1, 3101, true, 23, broadcast,
                   "broadcast bank1 data");
}

void test_read_injection() {
    std::cout << "RUN_TEST read_injection" << '\n';
    MemSliceModel model;
    MemSliceModel::Inputs inputs{};
    const Segments data0{0xA0, 0xA1, 0xA2, 0xA3};
    const Segments data1{0xC0, 0xC1, 0xC2, 0xC3};
    write_row(model, inputs, 0, 3200, false, 1, data0);
    write_row(model, inputs, 1, 3201, true, 2, data1);

    const auto read0 = make_command(kRead, false, 24, 3200);
    const auto read1 = make_command(kRead, true, 25, 3201);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs, tile == 0U, read0,
                                       tile == 0U, read1);
        const auto& inject0 = outputs.injection[0][tile];
        const auto& inject1 = outputs.injection[1][tile];
        expect(injection_count(outputs) == 2U &&
                   inject0.valid && inject0.data == data0[tile] &&
                   !inject0.stream_dir && inject0.stream_idx == 24U &&
                   inject1.valid && inject1.data == data1[tile] &&
                   inject1.stream_dir && inject1.stream_idx == 25U,
               "dual Read injection mismatch");
    }
}

void test_writetap_and_invalid_write() {
    std::cout << "RUN_TEST writetap_and_invalid_write" << '\n';
    MemSliceModel model;
    MemSliceModel::Inputs inputs{};
    const Segments old_data{10, 11, 12, 13};
    const Segments new_data{20, 21, 22, 23};
    const std::array<bool, 4> sparse{true, false, true, true};
    write_row(model, inputs, 0, 3300, false, 1, old_data);
    set_selector(inputs, false, 3, sparse, new_data);
    const auto tap = make_command(kWrite, false, 3, 3300, true);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs, tile == 0U, tap,
                                       false, 0);
        expect(consume_count(outputs) == 0U && !outputs.fault[0].valid,
               "WriteTap consume/fault mismatch");
    }
    const Segments tap_expected{20, 11, 22, 23};
    check_read_row(model, inputs, 0, 3300, true, 26, tap_expected,
                   "WriteTap sparse data");

    write_row(model, inputs, 1, 3301, true, 4, old_data);
    const std::array<bool, 4> tile2_invalid{true, true, false, true};
    set_selector(inputs, true, 5, tile2_invalid, new_data);
    const auto normal = make_command(kWrite, true, 5, 3301);
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs, false, 0,
                                       tile == 0U, normal);
        if (tile == 2U) {
            expect(!outputs.consume[1][1][5][tile] &&
                       outputs.fault[1].valid &&
                       outputs.fault[1].code ==
                           MemSliceModel::FaultCode::LEAF &&
                       outputs.fault[1].tile_id == 2U,
                   "invalid normal Write fault mismatch");
        } else {
            expect(outputs.consume[1][1][5][tile] &&
                       !outputs.fault[1].valid,
                   "valid normal Write segment mismatch");
        }
    }
    const Segments normal_expected{20, 21, 12, 23};
    check_read_row(model, inputs, 1, 3301, false, 27, normal_expected,
                   "invalid normal Write data");
}

void test_issue_legality_and_collision() {
    std::cout << "RUN_TEST issue_legality_and_collision" << '\n';
    MemSliceModel model;
    MemSliceModel::Inputs inputs{};
    const std::array<std::uint32_t, 4> illegal{
        make_command(2, false, 1, 3400),
        make_command(kRead, false, 1, 3401, true),
        make_command(kWrite, false, 1, 3402, false, 1),
        make_command(kWrite, false, 1, 3403, false, 0, true)};

    for (const auto command : illegal) {
        auto outputs = run_cycle(model, inputs, true, command, false, 0);
        expect(outputs.fault[0].valid &&
                   outputs.fault[0].code == MemSliceModel::FaultCode::ISSUE &&
                   !outputs.bank_busy[0] && consume_count(outputs) == 0U &&
                   injection_count(outputs) == 0U,
               "illegal issue gating mismatch");
        outputs = idle_cycle(model, inputs);
        expect(!outputs.fault[0].valid && !outputs.bank_busy[0],
               "illegal issue entered pipeline or fault did not clear");
    }

    const Segments data{40, 41, 42, 43};
    write_row(model, inputs, 0, 3410, false, 2, data);
    const auto read = make_command(kRead, true, 28, 3410);
    inputs.producer_collision[0] = {true, true, true, true};
    for (std::size_t tile = 0; tile < 4; ++tile) {
        const auto outputs = run_cycle(model, inputs, tile == 0U, read,
                                       false, 0);
        expect(outputs.injection[0][tile].valid &&
                   outputs.injection[0][tile].data == data[tile] &&
                   outputs.fault[0].valid &&
                   outputs.fault[0].code ==
                       MemSliceModel::FaultCode::COLLISION &&
                   outputs.fault[0].tile_id == tile,
               "collision feedback or injection preservation mismatch");
    }
}

void test_reset_fault_priority_and_raw() {
    std::cout << "RUN_TEST reset_fault_priority_and_raw" << '\n';
    MemSliceModel model;
    MemSliceModel::Inputs inputs{};
    const Segments data{50, 51, 52, 53};
    write_row(model, inputs, 0, 3500, false, 1, data);

    // Create Read A, invalid-normal-Write B, then illegal issue C. At the
    // third step: C issue fault, A collision, and B leaf fault coexist.
    inputs.sr_state = {};
    const auto read_a = make_command(kRead, false, 6, 3500);
    const auto write_b = make_command(kWrite, false, 7, 3501);
    const auto illegal_c = make_command(7, false, 8, 3502);
    run_cycle(model, inputs, true, read_a, false, 0);
    run_cycle(model, inputs, true, write_b, false, 0);
    inputs.producer_collision[0][2] = true;
    auto outputs = run_cycle(model, inputs, true, illegal_c, false, 0);
    expect(outputs.injection[0][2].valid && outputs.fault[0].valid &&
               outputs.fault[0].code == MemSliceModel::FaultCode::ISSUE &&
               !outputs.fault[0].tile_valid,
           "issue fault diagnostic priority mismatch");

    inputs.producer_collision[0] = {false, false, false, true};
    outputs = idle_cycle(model, inputs);
    expect(outputs.injection[0][3].valid && outputs.fault[0].valid &&
               outputs.fault[0].code ==
                   MemSliceModel::FaultCode::COLLISION &&
               outputs.fault[0].tile_id == 3U,
           "collision-over-leaf diagnostic priority mismatch");

    model.reset();
    inputs = {};
    outputs = idle_cycle(model, inputs);
    expect(!outputs.slice_busy && !outputs.fault[0].valid &&
               !outputs.fault[1].valid && injection_count(outputs) == 0U &&
               consume_count(outputs) == 0U && model.cycle() == 1U,
           "reset transient/control state mismatch");

    const Segments raw_data{
        0x0102030405060708ULL, 0x1112131415161718ULL,
        0x2122232425262728ULL, 0x3132333435363738ULL};
    const std::array<bool, 4> all_valid{true, true, true, true};
    set_selector(inputs, true, 9, all_valid, raw_data);
    const auto write = make_command(kWrite, true, 9, 3510);
    const auto read = make_command(kRead, false, 29, 3510);
    run_cycle(model, inputs, true, write, false, 0);
    for (std::size_t cycle = 1; cycle <= 4; ++cycle) {
        outputs = run_cycle(model, inputs, cycle == 1U, read, false, 0);
        const std::size_t tile = cycle - 1U;
        expect(outputs.injection[0][tile].valid &&
                   outputs.injection[0][tile].data == raw_data[tile],
               "Slice-level RAW mismatch");
    }
}

}  // namespace

int main() {
    test_dual_bank_independence_and_parallelism();
    test_sr_write_selection_and_broadcast_consume();
    test_read_injection();
    test_writetap_and_invalid_write();
    test_issue_legality_and_collision();
    test_reset_fault_priority_and_raw();

    if (failures == 0) {
        std::cout << "CMODEL_MEM_SLICE TEST_PASS" << '\n';
        return 0;
    }

    std::cout << "CMODEL_MEM_SLICE TEST_FAIL failures="
              << failures << '\n';
    return 1;
}
