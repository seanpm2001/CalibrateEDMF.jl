using Test
using CalibrateEDMF.ReferenceModels
using CalibrateEDMF.TurbulenceConvectionUtils


@testset "TurbulenceConvectionUtils" begin
    @test get_gcm_les_uuid(1, forcing_model = "model1", month = 1, experiment = "experiment1") ==
          "1_model1_01_experiment1"
end

@testset "TC.jl error handling" begin
    # Choose same SCM to speed computation
    data_dir = mktempdir()
    scm_dirs = [joinpath(data_dir, "Output.Bomex.000000")]
    # Violate CFL condition for TC.jl simulation to fail
    t_max = 2 * 3600.0
    namelist_args = [
        ("time_stepping", "t_max", t_max),
        ("time_stepping", "dt_max", 200.0),
        ("time_stepping", "dt_min", 200.0),
        ("grid", "dz", 150.0),
        ("grid", "nz", 20),
        ("stats_io", "frequency", 720.0),
    ]
    kwargs_ref_model = Dict(
        :y_names => [["u_mean", "v_mean"]],
        :y_dir => scm_dirs,
        :scm_dir => scm_dirs,
        :case_name => ["Bomex"],
        :t_start => [t_max - 3600],
        :t_end => [t_max],
        :Σ_t_start => [t_max - 2.0 * 3600],
        :Σ_t_end => [t_max],
    )
    ref_models = construct_reference_models(kwargs_ref_model)
    run_reference_SCM.(ref_models, run_single_timestep = false, namelist_args = namelist_args)

    u = [0.15]
    u_names = ["entrainment_factor"]
    res_dir, model_error = run_SCM_handler(ref_models[1], data_dir, u, u_names, namelist_args)

    @test model_error
end
