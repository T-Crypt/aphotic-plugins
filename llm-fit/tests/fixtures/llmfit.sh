#!/usr/bin/env bash

if [[ "$1" == "recommend" ]]; then
    printf '%s\n' '{"system":{"cpu_name":"Test CPU","cpu_cores":8,"total_ram_gb":16,"has_gpu":false},"models":[{"name":"test-model","best_quant":"Q4_K_M","fit_level":"Good","estimated_tps":42,"parameter_count":"8B","score":90,"ollama_name":"test-model:8b"}]}'
    exit 0
fi

exit 2
