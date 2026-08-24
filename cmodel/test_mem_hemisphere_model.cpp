#include "mem_hemisphere_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

constexpr std::uint8_t kRead = 0;
constexpr std::uint8_t kWrite = 1;
constexpr std::size_t kTestDepth = 16;
using Segments = std::array<std::uint64_t, MemHemisphereModel::TILES>;

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
           (static_cast<std::uint32_t>(direction) << 8U) |
           ((static_cast<std::uint32_t>(stream) & 0x1FU) << 3U) |
           (static_cast<std::uint32_t>(opcode) & 0x7U);
}

void set_selector(MemHemisphereModel::Inputs& inputs,
                  const std::size_t boundary,
                  const bool direction,
                  const std::uint8_t stream,
                  const Segments& data) {
    const std::size_t dir = direction ? 1U : 0U;
    for (std::size_t tile = 0; tile < MemHemisphereModel::TILES; ++tile) {
        inputs.boundary_state[boundary][dir][stream][tile].valid = true;
        inputs.boundary_state[boundary][dir][stream][tile].data = data[tile];
    }
}

MemHemisphereModel::Outputs run_cycle(
    MemHemisphereModel& model,
    MemHemisphereModel::Inputs& inputs,
    const MemHemisphereModel::IssueValid& valid,
    const MemHemisphereModel::IssueRaw& raw) {
    inputs.issue_valid = valid;
    inputs.issue_raw = raw;
    return model.step(inputs);
}

MemHemisphereModel::Outputs idle_cycle(
    MemHemisphereModel& model, MemHemisphereModel::Inputs& inputs) {
    return run_cycle(model, inputs, {}, {});
}

void write_row(MemHemisphereModel& model,
               MemHemisphereModel::Inputs& inputs,
               const std::size_t slice,
               const std::size_t bank,
               const std::uint16_t row,
               const bool direction,
               const std::uint8_t stream,
               const Segments& data) {
    const std::size_t group = slice / MemHemisphereModel::SLICES_PER_GROUP;
    const std::size_t input_boundary = direction ? group + 1U : group;
    set_selector(inputs, input_boundary, direction, stream, data);
    MemHemisphereModel::IssueRaw raw{};
    raw[slice][bank] = make_command(kWrite, direction, stream, row);
    for (std::size_t tile = 0; tile < MemHemisphereModel::TILES; ++tile) {
        MemHemisphereModel::IssueValid valid{};
        valid[slice][bank] = tile == 0U;
        run_cycle(model, inputs, valid, raw);
    }
}

void check_read_row(MemHemisphereModel& model,
                    MemHemisphereModel::Inputs& inputs,
                    const std::size_t slice,
                    const std::size_t bank,
                    const std::uint16_t row,
                    const bool direction,
                    const std::uint8_t stream,
                    const Segments& expected,
                    const std::string& name) {
    const std::size_t group = slice / MemHemisphereModel::SLICES_PER_GROUP;
    const std::size_t expected_boundary = direction ? group : group + 1U;
    MemHemisphereModel::IssueRaw raw{};
    raw[slice][bank] = make_command(kRead, direction, stream, row);
    for (std::size_t tile = 0; tile < MemHemisphereModel::TILES; ++tile) {
        MemHemisphereModel::IssueValid valid{};
        valid[slice][bank] = tile == 0U;
        const auto outputs = run_cycle(model, inputs, valid, raw);
        const std::size_t producer_id = slice * 8U + bank * 4U + tile;
        const auto& producer = outputs.producer[producer_id];
        expect(producer.valid && producer.data == expected[tile] &&
                   producer.stream_dir == direction &&
                   producer.stream_idx == stream &&
                   producer.boundary == expected_boundary,
               name + " producer/boundary mismatch");
    }
}

std::size_t producer_count(const MemHemisphereModel::Outputs& outputs) {
    std::size_t count = 0;
    for (const auto& producer : outputs.producer) {
        count += producer.valid ? 1U : 0U;
    }
    return count;
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

void test_topology_and_coordinates() {
    std::cout << "RUN_TEST topology_group_slice_coordinate_mapping" << '\n';
    expect(MemHemisphereModel::SLICES == 52U, "slice count");
    expect(MemHemisphereModel::GROUPS == 13U, "group count");
    expect(MemHemisphereModel::BOUNDARIES == 14U, "boundary count");
    expect(MemHemisphereModel::PRODUCERS == 416U, "producer count");
    expect(52U * 2U == 104U, "default capacity in MiB");

    MemHemisphereModel model(kTestDepth);
    MemHemisphereModel::Inputs inputs{};
    const Segments data{0x10, 0x11, 0x12, 0x13};
    write_row(model, inputs, 24, 1, 1, false, 2, data);
    check_read_row(model, inputs, 24, 1, 1, false, 3, data,
                   "group6 slice0 global coordinate");
}

void test_representative_groups_and_endpoints() {
    std::cout << "RUN_TEST representative_group0_group6_group12_mapping" << '\n';
    MemHemisphereModel model(kTestDepth);
    MemHemisphereModel::Inputs inputs{};
    const Segments east0{0x20, 0x21, 0x22, 0x23};
    const Segments west6{0x30, 0x31, 0x32, 0x33};
    const Segments east12{0x40, 0x41, 0x42, 0x43};
    const Segments west0{0x50, 0x51, 0x52, 0x53};

    write_row(model, inputs, 0, 0, 2, false, 4, east0);
    write_row(model, inputs, 27, 1, 3, true, 5, west6);
    write_row(model, inputs, 48, 0, 4, false, 6, east12);
    write_row(model, inputs, 3, 1, 5, true, 7, west0);
    check_read_row(model, inputs, 0, 0, 2, false, 8, east0,
                   "group0 East boundary1");
    check_read_row(model, inputs, 27, 1, 3, true, 9, west6,
                   "group6 West boundary6");
    check_read_row(model, inputs, 48, 0, 4, false, 10, east12,
                   "group12 East boundary13");
    check_read_row(model, inputs, 3, 1, 5, true, 11, west0,
                   "group0 West boundary0");
}

void test_shared_middle_boundary() {
    std::cout << "RUN_TEST shared_middle_boundary_direction_independence" << '\n';
    MemHemisphereModel model(kTestDepth);
    MemHemisphereModel::Inputs inputs{};
    const Segments east{0x60, 0x61, 0x62, 0x63};
    const Segments west{0x70, 0x71, 0x72, 0x73};
    write_row(model, inputs, 20, 0, 6, false, 1, east);
    write_row(model, inputs, 24, 0, 7, true, 2, west);

    MemHemisphereModel::IssueRaw raw{};
    raw[20][0] = make_command(kRead, false, 12, 6);
    raw[24][0] = make_command(kRead, true, 13, 7);
    for (std::size_t tile = 0; tile < 4U; ++tile) {
        MemHemisphereModel::IssueValid valid{};
        valid[20][0] = tile == 0U;
        valid[24][0] = tile == 0U;
        const auto outputs = run_cycle(model, inputs, valid, raw);
        const auto& east_producer = outputs.producer[20U * 8U + tile];
        const auto& west_producer = outputs.producer[24U * 8U + tile];
        expect(east_producer.valid && west_producer.valid &&
                   east_producer.boundary == 6U &&
                   west_producer.boundary == 6U &&
                   !east_producer.stream_dir && west_producer.stream_dir &&
                   !outputs.hemisphere_fault_valid,
               "shared boundary East/West separation");
    }
}

void test_distant_group_independence() {
    std::cout << "RUN_TEST distant_group_simultaneous_traffic" << '\n';
    MemHemisphereModel model(kTestDepth);
    MemHemisphereModel::Inputs inputs{};
    const Segments data0{0x80, 0x81, 0x82, 0x83};
    const Segments data6{0x90, 0x91, 0x92, 0x93};
    const Segments data12{0xA0, 0xA1, 0xA2, 0xA3};
    write_row(model, inputs, 0, 0, 8, false, 1, data0);
    write_row(model, inputs, 24, 0, 9, false, 2, data6);
    write_row(model, inputs, 48, 0, 10, true, 3, data12);

    MemHemisphereModel::IssueRaw raw{};
    raw[0][0] = make_command(kRead, false, 16, 8);
    raw[24][0] = make_command(kRead, false, 17, 9);
    raw[48][0] = make_command(kRead, true, 18, 10);
    for (std::size_t tile = 0; tile < 4U; ++tile) {
        MemHemisphereModel::IssueValid valid{};
        valid[0][0] = tile == 0U;
        valid[24][0] = tile == 0U;
        valid[48][0] = tile == 0U;
        const auto outputs = run_cycle(model, inputs, valid, raw);
        expect(producer_count(outputs) == 3U &&
                   outputs.producer[tile].boundary == 1U &&
                   outputs.producer[24U * 8U + tile].boundary == 7U &&
                   outputs.producer[48U * 8U + tile].boundary == 12U &&
                   !outputs.hemisphere_fault_valid,
               "distant Groups interfered");
    }
}

void test_external_collision_routing() {
    std::cout << "RUN_TEST external_collision_endpoint_middle_routing" << '\n';
    MemHemisphereModel model(kTestDepth);
    MemHemisphereModel::Inputs inputs{};
    const Segments data{0xB0, 0xB1, 0xB2, 0xB3};
    write_row(model, inputs, 0, 0, 11, true, 1, data);
    write_row(model, inputs, 20, 0, 12, false, 2, data);
    write_row(model, inputs, 48, 0, 13, false, 3, data);
    for (std::size_t tile = 0; tile < 4U; ++tile) {
        inputs.external_collision[0][tile] = true;
        inputs.external_collision[6][20U * 8U + tile] = true;
        inputs.external_collision[13][48U * 8U + tile] = true;
    }

    MemHemisphereModel::IssueRaw raw{};
    raw[0][0] = make_command(kRead, true, 20, 11);
    raw[20][0] = make_command(kRead, false, 21, 12);
    raw[48][0] = make_command(kRead, false, 22, 13);
    for (std::size_t tile = 0; tile < 4U; ++tile) {
        MemHemisphereModel::IssueValid valid{};
        valid[0][0] = tile == 0U;
        valid[20][0] = tile == 0U;
        valid[48][0] = tile == 0U;
        const auto outputs = run_cycle(model, inputs, valid, raw);
        expect(outputs.group_fault_valid[0] &&
                   outputs.group_fault_valid[5] &&
                   outputs.group_fault_valid[12] &&
                   outputs.hemisphere_fault_valid &&
                   outputs.group[0].slice[0].fault[0].code ==
                       MemSliceModel::FaultCode::COLLISION &&
                   outputs.group[5].slice[0].fault[0].code ==
                       MemSliceModel::FaultCode::COLLISION &&
                   outputs.group[12].slice[0].fault[0].code ==
                       MemSliceModel::FaultCode::COLLISION,
               "external collision owner routing");
    }
}

void test_continuous_traffic_and_reset() {
    std::cout << "RUN_TEST continuous_multi_group_traffic_and_reset" << '\n';
    MemHemisphereModel model(kTestDepth);
    MemHemisphereModel::Inputs inputs{};
    const Segments read0{0xC0, 0xC1, 0xC2, 0xC3};
    const Segments read12{0xD0, 0xD1, 0xD2, 0xD3};
    const Segments write6{0xE0, 0xE1, 0xE2, 0xE3};
    write_row(model, inputs, 0, 0, 14, false, 1, read0);
    write_row(model, inputs, 48, 0, 15, true, 2, read12);
    for (std::size_t stream = 0; stream < 4U; ++stream) {
        set_selector(inputs, 6, false, static_cast<std::uint8_t>(stream),
                     write6);
    }

    for (std::size_t cycle = 0; cycle < 4U; ++cycle) {
        MemHemisphereModel::IssueValid valid{};
        MemHemisphereModel::IssueRaw raw{};
        valid[0][0] = true;
        valid[24][0] = true;
        valid[48][0] = true;
        raw[0][0] = make_command(kRead, false,
            static_cast<std::uint8_t>(24U + cycle), 14);
        raw[24][0] = make_command(kWrite, false,
            static_cast<std::uint8_t>(cycle),
            static_cast<std::uint16_t>(cycle));
        raw[48][0] = make_command(kRead, true,
            static_cast<std::uint8_t>(28U + cycle), 15);
        const auto outputs = run_cycle(model, inputs, valid, raw);
        if (cycle == 3U) {
            expect(producer_count(outputs) == 8U &&
                       consume_count(outputs.boundary_consume[6]) == 4U &&
                       outputs.group_busy[0] && outputs.group_busy[6] &&
                       outputs.group_busy[12] &&
                       !outputs.hemisphere_fault_valid,
                   "continuous steady-state mismatch");
        }
    }
    for (std::size_t drain = 0; drain < 3U; ++drain) {
        const auto outputs = idle_cycle(model, inputs);
        const std::size_t expected = 3U - drain;
        expect(producer_count(outputs) == expected * 2U &&
                   consume_count(outputs.boundary_consume[6]) == expected &&
                   !outputs.hemisphere_fault_valid,
               "continuous drain mismatch");
    }
    model.reset();
    const auto outputs = idle_cycle(model, inputs);
    expect(model.cycle() == 1U && !outputs.hemisphere_busy &&
               !outputs.hemisphere_fault_valid &&
               producer_count(outputs) == 0U,
           "Hemisphere reset transient state");
}

}  // namespace

int main() {
    test_topology_and_coordinates();
    test_representative_groups_and_endpoints();
    test_shared_middle_boundary();
    test_distant_group_independence();
    test_external_collision_routing();
    test_continuous_traffic_and_reset();

    if (failures == 0) {
        std::cout << "CMODEL_MEM_HEMISPHERE TEST_PASS" << '\n';
        return 0;
    }
    std::cout << "CMODEL_MEM_HEMISPHERE TEST_FAIL failures="
              << failures << '\n';
    return 1;
}
