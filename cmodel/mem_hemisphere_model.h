#ifndef MEM_HEMISPHERE_MODEL_H
#define MEM_HEMISPHERE_MODEL_H

#include "mem_group_model.h"

#include <array>
#include <cstddef>
#include <cstdint>

class MemHemisphereModel {
public:
    static constexpr std::size_t SLICES = 52;
    static constexpr std::size_t SLICES_PER_GROUP = MemGroupModel::SLICES;
    static constexpr std::size_t GROUPS = SLICES / SLICES_PER_GROUP;
    static constexpr std::size_t BOUNDARIES = GROUPS + 1;
    static constexpr std::size_t BANKS = MemGroupModel::BANKS;
    static constexpr std::size_t TILES = MemGroupModel::TILES;
    static constexpr std::size_t PRODUCERS_PER_GROUP =
        SLICES_PER_GROUP * BANKS * TILES;
    static constexpr std::size_t PRODUCERS =
        SLICES * BANKS * TILES;

    using IssueValid = std::array<std::array<bool, BANKS>, SLICES>;
    using IssueRaw =
        std::array<std::array<std::uint32_t, BANKS>, SLICES>;
    using BoundaryState =
        std::array<MemSliceModel::SrState, BOUNDARIES>;
    using BoundaryConsume =
        std::array<MemSliceModel::ConsumeDirectionState, BOUNDARIES>;
    using BoundaryCollision =
        std::array<std::array<bool, PRODUCERS>, BOUNDARIES>;

    struct Inputs {
        IssueValid issue_valid{};
        IssueRaw issue_raw{};
        BoundaryState boundary_state{};
        BoundaryCollision external_collision{};
    };

    struct Producer {
        bool valid = false;
        std::uint64_t data = 0;
        bool stream_dir = false;
        std::uint8_t stream_idx = 0;
        std::uint8_t boundary = 0;
        std::uint8_t group = 0;
        std::uint8_t local_slice = 0;
        std::uint8_t bank = 0;
        std::uint8_t tile = 0;
    };

    struct Outputs {
        BoundaryConsume boundary_consume{};
        std::array<Producer, PRODUCERS> producer{};
        std::array<bool, PRODUCERS> internal_collision{};
        std::array<MemGroupModel::Outputs, GROUPS> group{};
        std::array<bool, GROUPS> group_busy{};
        std::array<bool, GROUPS> group_fault_valid{};
        bool hemisphere_busy = false;
        bool hemisphere_fault_valid = false;
    };

    explicit MemHemisphereModel(
        std::size_t depth_rows =
            MemBankSuperlaneLeafModel::P_MEM_BANK_DEPTH_ROWS);

    void reset();
    Outputs step(const Inputs& inputs);
    std::uint64_t cycle() const;

private:
    std::array<MemGroupModel, GROUPS> groups_;
    std::uint64_t cycle_ = 0;
};

#endif
