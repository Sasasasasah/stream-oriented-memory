#include "mem_logical_bank_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

constexpr std::uint8_t kRead = 0;
constexpr std::uint8_t kWrite = 1;
constexpr std::size_t kTiles = MemLogicalBankModel::TILE_ROWS;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << message << '\n';
        ++failures;
    }
}

std::uint32_t make_command(const std::uint8_t opcode,
                           const bool stream_dir,
                           const std::uint8_t stream_idx,
                           const std::uint16_t row,
                           const bool preserve = false,
                           const std::uint8_t map_stream = 0,
                           const bool reserved = false) {
    const std::uint32_t stream =
        (static_cast<std::uint32_t>(stream_dir) << 5U) |
        (static_cast<std::uint32_t>(stream_idx) & 0x1FU);
    return (static_cast<std::uint32_t>(preserve) << 31U) |
           (static_cast<std::uint32_t>(reserved) << 30U) |
           ((static_cast<std::uint32_t>(row) & 0x7FFFU) << 15U) |
           ((static_cast<std::uint32_t>(map_stream) & 0x3FU) << 9U) |
           ((stream & 0x3FU) << 3U) |
           (static_cast<std::uint32_t>(opcode) & 0x7U);
}

MemLogicalBankModel::Outputs step(
    MemLogicalBankModel& model,
    const bool command_valid,
    const std::uint32_t command,
    const std::array<bool, kTiles>& stream_valid = {},
    const std::array<std::uint64_t, kTiles>& stream_data = {}) {
    MemLogicalBankModel::Inputs inputs{};
    inputs.cmd_valid = command_valid;
    inputs.cmd_raw = command;
    inputs.stream_valid = stream_valid;
    inputs.stream_data = stream_data;
    return model.step(inputs);
}

std::uint8_t consume_mask(const MemLogicalBankModel::Outputs& outputs) {
    std::uint8_t mask = 0;
    for (std::size_t tile = 0; tile < kTiles; ++tile) {
        if (outputs.tile[tile].stream_consume) {
            mask = static_cast<std::uint8_t>(mask | (1U << tile));
        }
    }
    return mask;
}

std::uint8_t read_mask(const MemLogicalBankModel::Outputs& outputs) {
    std::uint8_t mask = 0;
    for (std::size_t tile = 0; tile < kTiles; ++tile) {
        if (outputs.tile[tile].read_valid) {
            mask = static_cast<std::uint8_t>(mask | (1U << tile));
        }
    }
    return mask;
}

std::uint8_t fault_mask(const MemLogicalBankModel::Outputs& outputs) {
    std::uint8_t mask = 0;
    for (std::size_t tile = 0; tile < kTiles; ++tile) {
        if (outputs.tile[tile].fault_valid) {
            mask = static_cast<std::uint8_t>(mask | (1U << tile));
        }
    }
    return mask;
}

void normal_write_wave(
    MemLogicalBankModel& model,
    const std::uint16_t row,
    const std::array<bool, kTiles>& valid,
    const std::array<std::uint64_t, kTiles>& data,
    const std::uint8_t expected_consume_mask,
    const std::uint8_t expected_fault_mask) {
    const auto command = make_command(kWrite, false, 3, row);
    for (std::size_t tile = 0; tile < kTiles; ++tile) {
        const auto outputs = step(model, tile == 0, command, valid, data);
        const auto tile_bit = static_cast<std::uint8_t>(1U << tile);
        expect(consume_mask(outputs) ==
                   static_cast<std::uint8_t>(expected_consume_mask & tile_bit),
               "normal Write consume mismatch");
        expect(fault_mask(outputs) ==
                   static_cast<std::uint8_t>(expected_fault_mask & tile_bit),
               "normal Write fault mismatch");
    }
}

std::array<std::uint64_t, kTiles> read_wave(
    MemLogicalBankModel& model,
    const std::uint16_t row,
    const bool direction,
    const std::uint8_t stream_index) {
    const auto command = make_command(kRead, direction, stream_index, row);
    std::array<std::uint64_t, kTiles> data{};
    for (std::size_t tile = 0; tile < kTiles; ++tile) {
        const auto outputs = step(model, tile == 0, command);
        expect(read_mask(outputs) == static_cast<std::uint8_t>(1U << tile),
               "Read response timing mismatch");
        expect(outputs.tile[tile].read_stream_dir == direction &&
                   outputs.tile[tile].read_stream_idx == stream_index,
               "Read stream metadata mismatch");
        data[tile] = outputs.tile[tile].read_data;
    }
    return data;
}

void test_control_wave_and_bubble() {
    std::cout << "RUN_TEST control_wave_and_bubble" << '\n';
    MemLogicalBankModel model;
    const std::array<bool, kTiles> all_valid{true, true, true, true};
    const std::array<std::uint64_t, kTiles> data{1, 2, 3, 4};
    const auto command_a = make_command(kWrite, false, 1, 5);
    const auto command_b = make_command(7, true, 31, 6);

    auto outputs = step(model, true, command_a, all_valid, data);
    expect(consume_mask(outputs) == 0x1U, "A must execute at tile0 in C");
    outputs = step(model, false, 0, all_valid, data);
    expect(consume_mask(outputs) == 0x2U, "A must execute at tile1 in C+1");
    outputs = step(model, true, command_b, all_valid, data);
    expect(consume_mask(outputs) == 0x4U && fault_mask(outputs) == 0x1U,
           "A/bubble/B placement mismatch at C+2");
    outputs = step(model, false, 0, all_valid, data);
    expect(consume_mask(outputs) == 0x8U && fault_mask(outputs) == 0x2U,
           "A/bubble/B placement mismatch at C+3");
    outputs = step(model, false, 0, all_valid, data);
    expect(consume_mask(outputs) == 0U && fault_mask(outputs) == 0x4U,
           "B must retain the bubble while advancing to tile2");
    outputs = step(model, false, 0, all_valid, data);
    expect(fault_mask(outputs) == 0x8U,
           "B must retain the bubble while advancing to tile3");
}

void test_continuous_issue() {
    std::cout << "RUN_TEST continuous_issue" << '\n';
    MemLogicalBankModel model;
    const std::array<bool, kTiles> all_valid{true, true, true, true};
    const std::array<std::uint64_t, kTiles> data{10, 11, 12, 13};
    const std::array<std::uint32_t, 4> command{
        make_command(kWrite, false, 0, 10),
        make_command(kWrite, false, 1, 11),
        make_command(kWrite, true, 2, 12),
        make_command(kWrite, true, 3, 13)};
    const std::array<std::uint8_t, 4> fill_mask{0x1U, 0x3U, 0x7U, 0xFU};

    for (std::size_t cycle = 0; cycle < command.size(); ++cycle) {
        const auto outputs = step(model, true, command[cycle], all_valid, data);
        expect(consume_mask(outputs) == fill_mask[cycle],
               "continuous II=1 fill mismatch");
        if (cycle == 3) {
            expect(outputs.north_cmd_valid &&
                       outputs.north_cmd == command[0],
                   "continuous first north command mismatch");
        }
    }

    const std::array<std::uint8_t, 4> drain_mask{0xEU, 0xCU, 0x8U, 0x0U};
    for (std::size_t cycle = 0; cycle < drain_mask.size(); ++cycle) {
        const auto outputs = step(model, false, 0, all_valid, data);
        expect(consume_mask(outputs) == drain_mask[cycle],
               "continuous II=1 drain mismatch");
        if (cycle < 3) {
            expect(outputs.north_cmd_valid &&
                       outputs.north_cmd == command[cycle + 1],
                   "continuous north command order mismatch");
        } else {
            expect(!outputs.north_cmd_valid,
                   "continuous north trace must drain");
        }
    }
}

void test_four_leaf_write_and_read() {
    std::cout << "RUN_TEST four_leaf_write_and_read" << '\n';
    MemLogicalBankModel model;
    const std::array<bool, kTiles> all_valid{true, true, true, true};
    const std::array<std::uint64_t, kTiles> data{
        0xD0D0D0D0D0D0D0D0ULL, 0xD1D1D1D1D1D1D1D1ULL,
        0xD2D2D2D2D2D2D2D2ULL, 0xD3D3D3D3D3D3D3D3ULL};

    normal_write_wave(model, 20, all_valid, data, 0xFU, 0U);
    expect(read_wave(model, 20, true, 17) == data,
           "four independent leaf segments must read back correctly");
}

void test_writetap_and_invalid_write() {
    std::cout << "RUN_TEST writetap_and_invalid_write" << '\n';
    MemLogicalBankModel model;
    const std::array<bool, kTiles> all_valid{true, true, true, true};
    const std::array<std::uint64_t, kTiles> tap_data{
        0xA0A0A0A0A0A0A0A0ULL, 0xA1A1A1A1A1A1A1A1ULL,
        0xA2A2A2A2A2A2A2A2ULL, 0xA3A3A3A3A3A3A3A3ULL};
    const auto tap = make_command(kWrite, false, 4, 21, true);

    for (std::size_t tile = 0; tile < kTiles; ++tile) {
        const auto outputs = step(model, tile == 0, tap, all_valid, tap_data);
        expect(consume_mask(outputs) == 0U && fault_mask(outputs) == 0U,
               "WriteTap must write without consume or fault");
    }
    expect(read_wave(model, 21, false, 4) == tap_data,
           "WriteTap data mismatch");

    const std::array<std::uint64_t, kTiles> old_data{100, 101, 102, 103};
    const std::array<std::uint64_t, kTiles> new_data{200, 201, 202, 203};
    normal_write_wave(model, 22, all_valid, old_data, 0xFU, 0U);
    const std::array<bool, kTiles> tile2_invalid{true, true, false, true};
    normal_write_wave(model, 22, tile2_invalid, new_data, 0xBU, 0x4U);
    const std::array<std::uint64_t, kTiles> expected{200, 201, 102, 203};
    expect(read_wave(model, 22, true, 5) == expected,
           "invalid normal Write must not modify its leaf");
}

void test_raw() {
    std::cout << "RUN_TEST raw" << '\n';
    MemLogicalBankModel model;
    const std::array<bool, kTiles> all_valid{true, true, true, true};
    const std::array<std::uint64_t, kTiles> data{
        0x0102030405060708ULL, 0x1112131415161718ULL,
        0x2122232425262728ULL, 0x3132333435363738ULL};
    const auto write = make_command(kWrite, false, 6, 30);
    const auto read = make_command(kRead, true, 9, 30);

    step(model, true, write, all_valid, data);
    for (std::size_t cycle = 1; cycle <= kTiles; ++cycle) {
        const auto outputs = step(model, cycle == 1, read, all_valid, data);
        const std::size_t tile = cycle - 1;
        expect(read_mask(outputs) == static_cast<std::uint8_t>(1U << tile),
               "RAW Read response timing mismatch");
        expect(outputs.tile[tile].read_data == data[tile],
               "RAW Read must observe the preceding Write");
    }
}

void test_reset_pulse_busy_and_north() {
    std::cout << "RUN_TEST reset_pulse_busy_and_north" << '\n';
    MemLogicalBankModel model;
    model.reset();
    auto outputs = step(model, false, 0);
    expect(!outputs.pipeline_busy && !outputs.north_cmd_valid &&
               consume_mask(outputs) == 0U && read_mask(outputs) == 0U &&
               fault_mask(outputs) == 0U,
           "reset state must be empty");

    const std::array<bool, kTiles> all_valid{true, true, true, true};
    const std::array<std::uint64_t, kTiles> data{40, 41, 42, 43};
    const auto raw = make_command(kWrite, true, 23, 40,
                                  false, 0x2AU, true);
    outputs = step(model, true, raw, all_valid, data);
    expect(outputs.pipeline_busy && consume_mask(outputs) == 0x1U,
           "pipeline busy fill mismatch");
    for (std::size_t cycle = 1; cycle < kTiles; ++cycle) {
        outputs = step(model, false, 0, all_valid, data);
        expect(outputs.pipeline_busy &&
                   consume_mask(outputs) ==
                       static_cast<std::uint8_t>(1U << cycle),
               "pipeline busy drain or pulse clear mismatch");
        if (cycle == 3) {
            expect(outputs.north_cmd_valid && outputs.north_cmd == raw,
                   "registered north trace mismatch");
        }
    }
    outputs = step(model, false, 0);
    expect(!outputs.pipeline_busy && !outputs.north_cmd_valid &&
               consume_mask(outputs) == 0U,
           "registered north trace or final pulse did not clear");

    step(model, true, raw, all_valid, data);
    model.reset();
    outputs = step(model, false, 0);
    expect(!outputs.pipeline_busy && !outputs.north_cmd_valid &&
               consume_mask(outputs) == 0U && model.cycle() == 1,
           "reset must clear in-flight control and restart cycle count");
}

}  // namespace

int main() {
    test_control_wave_and_bubble();
    test_continuous_issue();
    test_four_leaf_write_and_read();
    test_writetap_and_invalid_write();
    test_raw();
    test_reset_pulse_busy_and_north();

    if (failures == 0) {
        std::cout << "CMODEL_LOGICAL_BANK TEST_PASS" << '\n';
        return 0;
    }

    std::cout << "CMODEL_LOGICAL_BANK TEST_FAIL failures="
              << failures << '\n';
    return 1;
}
