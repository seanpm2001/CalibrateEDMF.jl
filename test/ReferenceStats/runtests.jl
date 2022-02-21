using Test
using LinearAlgebra
import CalibrateEDMF.ModelTypes
using CalibrateEDMF.ReferenceModels
using CalibrateEDMF.ReferenceStats
using CalibrateEDMF.TurbulenceConvectionUtils

@testset "ReferenceStatistics" begin
    # Choose same SCM to speed computation
    data_dir = mktempdir()
    scm_dirs = repeat([joinpath(data_dir, "Output.Bomex.000000")], 2)
    # Reduce resolution and t_max to speed computation as well
    t_max = 4 * 3600.0
    dt_max = 30.0
    dt_min = 20.0
    io_frequency = 120.0
    namelist_args = [
        ("time_stepping", "t_max", t_max),
        ("time_stepping", "dt_max", dt_max),
        ("time_stepping", "dt_min", dt_min),
        ("grid", "dz", 150.0),
        ("grid", "nz", 20),
        ("stats_io", "frequency", io_frequency),
    ]
    kwargs_ref_model = Dict(
        :y_names => [["u_mean"], ["v_mean"]],
        :y_dir => scm_dirs,
        :scm_dir => scm_dirs,
        :case_name => repeat(["Bomex"], 2),
        :t_start => repeat([t_max - 2.0 * 3600], 2),
        :t_end => repeat([t_max], 2),
    )
    ref_models = construct_reference_models(kwargs_ref_model)
    run_reference_SCM.(ref_models, overwrite = false, run_single_timestep = false, namelist_args = namelist_args)

    # Test penalty behavior of ReferenceStatistics.get_profile

    # if simulation lines up with ti, tf => no penalty
    y = ReferenceStats.get_profile(scm_dirs[1], ["u_mean", "v_mean"]; ti = 0.0, tf = t_max)
    @test maximum(y) < 1e4
    # if simulation end within dt margin => no penalty
    y = ReferenceStats.get_profile(scm_dirs[1], ["u_mean", "v_mean"]; ti = 0.0, tf = t_max + io_frequency)
    @test maximum(y) < 1e4
    # if simulation end outside of dt margin => penalty
    y = ReferenceStats.get_profile(scm_dirs[1], ["u_mean", "v_mean"]; ti = 0.0, tf = t_max + io_frequency + dt_max)
    @test all(y .> 1e4)
    # if simulation end after ti  => no penalty
    y = ReferenceStats.get_profile(scm_dirs[1], ["u_mean", "v_mean"]; ti = t_max - 0.01, tf = t_max)
    @test maximum(y) < 1e4
    # if simulation end before ti  => penalty
    y = ReferenceStats.get_profile(scm_dirs[1], ["u_mean", "v_mean"]; ti = t_max + 0.01, tf = t_max)
    @test all(y .> 1e4)

    # Test only tikhonov vs PCA and tikhonov
    pca_list = [false, true]
    norm_list = [false, true]
    mode_list = ["absolute", "relative"]
    dim_list = [false, true]
    for (pca, norm, tikhonov_mode, dim_scaling) in zip(pca_list, norm_list, mode_list, dim_list)
        ref_stats = ReferenceStatistics(
            ref_models;
            perform_PCA = pca,
            normalize = norm,
            variance_loss = 0.1,
            tikhonov_noise = 0.1,
            tikhonov_mode = tikhonov_mode,
            dim_scaling = dim_scaling,
            y_type = ModelTypes.SCM(),
            Σ_type = ModelTypes.SCM(),
        )

        @test pca_length(ref_stats) == size(ref_stats.Γ, 1)
        @test full_length(ref_stats) == size(ref_stats.Γ_full, 1)
        @test (pca_length(ref_stats) < full_length(ref_stats)) == pca
        if pca == false
            # Tikhonov regularization results in variance inflation
            @test tr(ref_stats.Γ) > tr(ref_stats.Γ_full)
            # Since the same configuration is added twice,
            # the full covariance is singular,
            @test det(ref_stats.Γ_full) ≈ 0
            # But not the regularized covariance.
            @test det(ref_stats.Γ) > 0
        end
    end

    # Verify that incorrect definitions throw error
    @test_throws AssertionError ReferenceStatistics(
        ref_models;
        perform_PCA = false,
        normalize = false,
        tikhonov_mode = "relative",
        y_type = ModelTypes.SCM(),
        Σ_type = ModelTypes.SCM(),
    )
end
