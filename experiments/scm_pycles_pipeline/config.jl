#= Custom calibration configuration file. =#

import ArtifactWrappers
const AW = ArtifactWrappers

function get_les_data_path()
    #! format: off
    PyCLES_output_dataset = AW.ArtifactWrapper(
        @__DIR__,
        isempty(get(ENV, "CI", "")),
        "PyCLES_output",
        AW.ArtifactFile[
        AW.ArtifactFile(url = "https://caltech.box.com/shared/static/d6oo7th33839qmp4z99n8z4ryk3iepoq.nc", filename = "Bomex.nc",),
        ],
    )
    PyCLES_output_dataset_path = AW.get_data_folder(PyCLES_output_dataset)
    return PyCLES_output_dataset_path
end

using Distributions
using StatsBase
using LinearAlgebra
using CalibrateEDMF
import CalibrateEDMF.ModelTypes
using CalibrateEDMF.LESUtils
using CalibrateEDMF.TurbulenceConvectionUtils
# Import prior constraints
using EnsembleKalmanProcesses.ParameterDistributions
using JLD2

# Cases defined as structs for quick access to default configs
struct Bomex end
struct LesDrivenScm end
# struct MyAwesomeSetup end

function get_config()
    config = Dict()
    # Flags for saving output data
    config["output"] = get_output_config()
    # Define regularization of inverse problem
    config["regularization"] = get_regularization_config()
    # Define reference used in the inverse problem 
    config["reference"] = get_reference_config(Bomex())
    # Define the parameter priors
    config["prior"] = get_prior_config()
    # Define the kalman process
    config["process"] = get_process_config()
    # Define the SCM static configuration
    config["scm"] = get_scm_config()
    return config
end

function get_output_config()
    config = Dict()
    config["outdir_root"] = pwd()
    config["overwrite_scm_file"] = false # Flag for overwritting SCM input file
    return config
end

function get_regularization_config()
    config = Dict()
    # Regularization of observations: mean and covariance
    config["perform_PCA"] = true # Performs PCA on data
    config["variance_loss"] = 1.0e-2 # Variance truncation level in PCA
    config["normalize"] = true  # whether to normalize data by pooled variance
    config["tikhonov_mode"] = "relative" # Tikhonov regularization
    config["tikhonov_noise"] = 1.0e-4 # Tikhonov regularization
    config["dim_scaling"] = true # Dimensional scaling of the loss

    # Parameter regularization: L2 regularization with respect to prior mean
    # Set to `nothing` or `0.0` to use prior covariance as regularizer.
    # To turn off regularization, set config["process"]["augmented"] to false.
    config["l2_reg"] = nothing
    return config
end

function get_process_config()
    config = Dict()
    config["N_iter"] = 4
    config["N_ens"] = 10
    config["algorithm"] = "Inversion" # "Sampler", "Unscented"
    config["noisy_obs"] = false
    # Artificial time stepper of the EKI.
    config["Δt"] = 1.0
    # Whether to augment the outputs with the parameters for regularization
    config["augmented"] = false
    config["failure_handler"] = "sample_succ_gauss"
    return config
end

function get_reference_config(::Bomex)
    config = Dict()
    config["case_name"] = ["Bomex"]
    # Flag to indicate source of data (LES or SCM) for reference data and covariance
    config["y_reference_type"] = ModelTypes.LES()
    config["Σ_reference_type"] = ModelTypes.LES()
    # "total_flux_qt" will be available in TC.jl version 0.5.0
    config["y_names"] = [["thetal_mean", "ql_mean", "qt_mean", "total_flux_h"]]
    config["y_dir"] = [get_les_data_path()]
    # provide list of dirs if different from `y_dir`
    # config["Σ_dir"] = [...]
    config["scm_suffix"] = ["000000"]
    config["scm_parent_dir"] = ["scm_init"]
    config["t_start"] = [4.0 * 3600]
    config["t_end"] = [6.0 * 3600]
    # Specify averaging intervals for covariance, if different from mean vector (`t_start` & `t_end`)
    # config["Σ_t_start"] = [...]
    # config["Σ_t_end"] = [...]
    config["batch_size"] = nothing
    return config
end


function get_reference_config(::LesDrivenScm)
    config = Dict()
    config["case_name"] = ["LES_driven_SCM"]
    # Flag to indicate whether reference data is from a perfect model (i.e. SCM instead of LES)
    config["y_reference_type"] = ModelTypes.LES()
    config["Σ_reference_type"] = ModelTypes.LES()
    config["y_names"] = [["thetal_mean", "ql_mean", "qt_mean"]]
    cfsite_number = 17
    les_kwargs = (forcing_model = "HadGEM2-A", month = 7, experiment = "amip")
    config["y_dir"] = [get_cfsite_les_dir(cfsite_number; les_kwargs...)]
    config["scm_suffix"] = [get_gcm_les_uuid(cfsite_number; les_kwargs...)]
    config["scm_parent_dir"] = ["scm_init"]
    config["t_start"] = [3.0 * 3600]
    config["t_end"] = [6.0 * 3600]
    # Use full LES timeseries for covariance
    config["Σ_t_start"] = [-5.75 * 24 * 3600]
    config["Σ_t_end"] = [6.0 * 3600]
    config["batch_size"] = nothing
    return config
end

function get_prior_config()
    config = Dict()
    config["constraints"] =
        Dict("entrainment_factor" => [bounded(0.0, 0.5)], "detrainment_factor" => [bounded(0.3, 0.8)])
    config["prior_mean"] = Dict("entrainment_factor" => [0.13], "detrainment_factor" => [0.51])
    config["unconstrained_σ"] = 0.5
    return config
end

function get_scm_config()
    config = Dict()
    # List of tuples like [("time_stepping", "dt_min", 1.0)], or nothing
    config["namelist_args"] = nothing
    return config
end
