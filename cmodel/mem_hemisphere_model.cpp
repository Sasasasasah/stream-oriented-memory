#include "mem_hemisphere_model.h"

MemHemisphereModel::MemHemisphereModel(const std::size_t depth_rows)
    : groups_{MemGroupModel(depth_rows), MemGroupModel(depth_rows),
              MemGroupModel(depth_rows), MemGroupModel(depth_rows),
              MemGroupModel(depth_rows), MemGroupModel(depth_rows),
              MemGroupModel(depth_rows), MemGroupModel(depth_rows),
              MemGroupModel(depth_rows), MemGroupModel(depth_rows),
              MemGroupModel(depth_rows), MemGroupModel(depth_rows),
              MemGroupModel(depth_rows)} {
    reset();
}

void MemHemisphereModel::reset() {
    for (auto& group : groups_) {
        group.reset();
    }
    cycle_ = 0;
}

MemHemisphereModel::Outputs MemHemisphereModel::step(
    const Inputs& inputs) {
    Outputs outputs{};
    std::array<MemGroupModel::Inputs, GROUPS> group_inputs{};

    // All Groups observe the same immutable cycle-start boundary snapshot.
    // There is deliberately no combinational Group-to-Group SR propagation.
    for (std::size_t group = 0; group < GROUPS; ++group) {
        group_inputs[group].left_boundary_state =
            inputs.boundary_state[group];
        group_inputs[group].right_boundary_state =
            inputs.boundary_state[group + 1U];
        for (std::size_t local_slice = 0;
             local_slice < SLICES_PER_GROUP; ++local_slice) {
            const std::size_t global_slice =
                group * SLICES_PER_GROUP + local_slice;
            group_inputs[group].issue_valid[local_slice] =
                inputs.issue_valid[global_slice];
            group_inputs[group].issue_raw[local_slice] =
                inputs.issue_raw[global_slice];
        }
        outputs.group[group] = groups_[group].step(group_inputs[group]);
    }

    for (std::size_t group = 0; group < GROUPS; ++group) {
        // A group consumes East streams from its left boundary and West
        // streams from its right boundary. Adjacent contributions are ORed.
        for (std::size_t direction = 0;
             direction < MemSliceModel::DIRECTIONS; ++direction) {
            for (std::size_t stream = 0;
                 stream < MemSliceModel::STREAMS; ++stream) {
                for (std::size_t tile = 0; tile < TILES; ++tile) {
                    outputs.boundary_consume[group][direction][stream][tile] =
                        outputs.boundary_consume[group][direction][stream][tile] ||
                        outputs.group[group]
                            .left_consume[direction][stream][tile];
                    outputs.boundary_consume[group + 1U]
                        [direction][stream][tile] =
                        outputs.boundary_consume[group + 1U]
                            [direction][stream][tile] ||
                        outputs.group[group]
                            .right_consume[direction][stream][tile];
                }
            }
        }

        for (std::size_t local_slice = 0;
             local_slice < SLICES_PER_GROUP; ++local_slice) {
            for (std::size_t bank = 0; bank < BANKS; ++bank) {
                for (std::size_t tile = 0; tile < TILES; ++tile) {
                    const std::size_t local_producer =
                        local_slice * BANKS * TILES + bank * TILES + tile;
                    const std::size_t global_producer =
                        group * PRODUCERS_PER_GROUP + local_producer;
                    const auto& left = outputs.group[group]
                        .left_producer[local_slice][bank][tile];
                    const auto& right = outputs.group[group]
                        .right_producer[local_slice][bank][tile];
                    const auto& source = left.valid ? left : right;
                    auto& producer = outputs.producer[global_producer];

                    producer.valid = source.valid;
                    producer.data = source.data;
                    producer.stream_dir = source.stream_dir;
                    producer.stream_idx = source.stream_idx;
                    producer.boundary = static_cast<std::uint8_t>(
                        left.valid ? group : group + 1U);
                    producer.group = static_cast<std::uint8_t>(group);
                    producer.local_slice =
                        static_cast<std::uint8_t>(local_slice);
                    producer.bank = static_cast<std::uint8_t>(bank);
                    producer.tile = static_cast<std::uint8_t>(tile);
                    outputs.internal_collision[global_producer] =
                        outputs.group[group]
                            .internal_collision[local_slice][bank][tile];
                }
            }
        }
    }

    // External collision resolution is boundary-local and producer-specific.
    // Route feedback only to the Group/Slice/Bank/Tile that owns the producer.
    for (std::size_t group = 0; group < GROUPS; ++group) {
        MemGroupModel::CollisionFeedback feedback{};
        for (std::size_t local_slice = 0;
             local_slice < SLICES_PER_GROUP; ++local_slice) {
            for (std::size_t bank = 0; bank < BANKS; ++bank) {
                for (std::size_t tile = 0; tile < TILES; ++tile) {
                    const std::size_t local_producer =
                        local_slice * BANKS * TILES + bank * TILES + tile;
                    const std::size_t global_producer =
                        group * PRODUCERS_PER_GROUP + local_producer;
                    const auto& producer = outputs.producer[global_producer];
                    feedback[local_slice][bank][tile] = producer.valid &&
                        inputs.external_collision[producer.boundary]
                                                  [global_producer];
                }
            }
        }
        groups_[group].apply_collision_feedback(feedback,
                                                 outputs.group[group]);
        outputs.group_busy[group] = outputs.group[group].group_busy;
        outputs.group_fault_valid[group] =
            outputs.group[group].group_fault_valid;
        outputs.hemisphere_busy = outputs.hemisphere_busy ||
                                  outputs.group_busy[group];
        outputs.hemisphere_fault_valid =
            outputs.hemisphere_fault_valid ||
            outputs.group_fault_valid[group];
    }

    ++cycle_;
    return outputs;
}

std::uint64_t MemHemisphereModel::cycle() const {
    return cycle_;
}
