using Test
using LinearAlgebra
using NCDatasets
using Random
const NC = NCDatasets
using CalibrateEDMF
import CalibrateEDMF.ModelTypes
using CalibrateEDMF.ReferenceModels
using CalibrateEDMF.ReferenceStats
using CalibrateEDMF.DistributionUtils
using CalibrateEDMF.TurbulenceConvectionUtils
using CalibrateEDMF.NetCDFIO
const CN = CalibrateEDMF.NetCDFIO
using EnsembleKalmanProcesses
using EnsembleKalmanProcesses.ParameterDistributions

@testset "NetCDFIO_Diags" begin
    # Choose same SCM to speed computation
    data_dir = mktempdir()
    t_max = 2 * 3600.0
    namelist_args = [
        ("time_stepping", "t_max", t_max),
        ("time_stepping", "dt_max", 30.0),
        ("time_stepping", "dt_min", 20.0),
        ("grid", "dz", 150.0),
        ("grid", "nz", 20),
        ("stats_io", "frequency", 120.0),
    ]
    scm_dirs = repeat([joinpath(data_dir, "Output.Bomex.000000")], 2)
    kwargs_ref_model = Dict(
        :y_names => [["u_mean"], ["v_mean"]],
        :y_dir => scm_dirs,
        :scm_dir => scm_dirs,
        :case_name => repeat(["Bomex"], 2),
        :t_start => repeat([t_max - 2.0 * 3600], 2),
        :t_end => repeat([t_max], 2),
    )
    # Generate ref_stats
    ref_models = construct_reference_models(kwargs_ref_model)
    run_reference_SCM.(ref_models, overwrite = false, run_single_timestep = false, namelist_args = namelist_args)
    ref_stats = ReferenceStatistics(ref_models, y_type = ModelTypes.SCM(), Σ_type = ModelTypes.SCM())
    # Generate config
    config = Dict()
    config["process"] = Dict()
    config["process"]["N_ens"] = 10
    config["process"]["batch_size"] = nothing
    config["prior"] = Dict()
    config["prior"]["constraints"] = Dict("foo" => [bounded(0.0, 0.5)], "bar" => [bounded(0.0, 0.5)])
    config["reference"] = Dict()
    priors = construct_priors(config["prior"]["constraints"])
    ekp = EnsembleKalmanProcess(rand(2, 10), ref_stats.y, ref_stats.Γ, Inversion())
    N_ens = size(get_u_final(ekp), 2)
    diags = NetCDFIO_Diags(config, data_dir, ref_stats, N_ens, priors)

    # Test constructor
    @test isa(diags, NetCDFIO_Diags)
    @test isempty(diags.vars)

    # Test reference diagnostics
    io_reference(diags, ref_stats, ref_models)
    NC.Dataset(diags.filepath, "r") do root_grp
        ref_grp = root_grp.group["reference"]
        @test ref_grp["Gamma"] ≈ ref_stats.Γ
        @test ref_grp["Gamma_full"] ≈ ref_stats.Γ_full
        @test ref_grp["y"] ≈ ref_stats.y
        @test ref_grp["y_full"] ≈ ref_stats.y_full
    end

    # Test iteration-dependent diagnostics
    CN.init_iteration_io(diags)
    CN.open_files(diags)
    CN.write_iteration(diags)
    CN.close_files(diags)
    NC.Dataset(diags.filepath, "r") do root_grp
        ensemble_grp = root_grp.group["ensemble_diags"]
        @test length(ensemble_grp["iteration"]) == 2
    end
end
