# This is an example on training the TurbulenceConvection.jl implementation
# of the EDMF scheme with data generated using PyCLES (an LES solver) or
# TurbulenceConvection.jl (perfect model setting).
#
# This example parallelizes forward model evaluations using Julia's pmap() function.
# This parallelization strategy is efficient for small ensembles (N_ens < 20). For
# calibration processes involving a larger number of ensemble members, parallelization
# using HPC resources directly is advantageous.

# Import modules to all processes
using Distributed
@everywhere using Pkg
@everywhere Pkg.activate(dirname(dirname(dirname(@__DIR__))))
@everywhere begin
    using ArgParse
    using CalibrateEDMF
    using CalibrateEDMF.DistributionUtils
    using CalibrateEDMF.Pipeline
    src_dir = dirname(pathof(CalibrateEDMF))
    using CalibrateEDMF.HelperFuncs
    # Import EKP modules
    using EnsembleKalmanProcesses
    using EnsembleKalmanProcesses.ParameterDistributions
end
# include(joinpath(@__DIR__, "../../../src/viz/ekp_plots.jl"))
using JLD2
import Dates

s = ArgParseSettings()
@add_arg_table s begin
    "--config"
    help = "Inverse problem config file path"
    arg_type = String
end
parsed_args = parse_args(ARGS, s)
include(parsed_args["config"])
config = get_config()

# Initialize calibration process
outdir_path = init_calibration(config; config_path = parsed_args["config"], mode = "pmap")
priors = deserialize_prior(load(joinpath(outdir_path, "prior.jld2")))

# Dispatch SCM eval functions to workers
@everywhere begin
    scm_eval_train(version) = versioned_model_eval(version, $outdir_path, "train", $config)
    scm_eval_validation(version) = versioned_model_eval(version, $outdir_path, "validation", $config)
end

# Calibration process
N_iter = config["process"]["N_iter"]
@info "Running EK updates for $N_iter iterations"
for iteration in 1:N_iter
    @time begin
        @info "   iter = $iteration"
        versions = readlines(joinpath(outdir_path, "versions_$(iteration).txt"))
        ekp = load(ekobj_path(outdir_path, iteration))["ekp"]
        pmap(scm_eval_train, versions)
        pmap(scm_eval_validation, versions)
        ek_update(ekp, priors, iteration, config, versions, outdir_path)
    end
end
@info "Calibration completed. $(Dates.now())"
