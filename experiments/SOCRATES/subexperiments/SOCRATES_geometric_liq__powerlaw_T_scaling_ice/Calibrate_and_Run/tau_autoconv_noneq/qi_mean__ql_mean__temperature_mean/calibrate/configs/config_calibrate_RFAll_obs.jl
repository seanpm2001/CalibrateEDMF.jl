#= Custom calibration configuration file. =#

# ========================================================================================================================= #
# this_dir = @__DIR__ # the location of this file (doens't work cause this gets copied and moved around both in HPC and in calibration pipeline)
using CalibrateEDMF
pkg_dir = pkgdir(CalibrateEDMF)
main_experiment_dir = joinpath(pkg_dir, "experiments", "SOCRATES")
include(joinpath(main_experiment_dir, "Calibrate_and_Run_scripts", "calibrate", "config_calibrate_template_header.jl")) # load the template config file for the rest of operations
# ========================================================================================================================= #
# experiment (should match this directory names)
supersat_type = :geometric_liq__powerlaw_T_scaling_ice
# calibration_setup (should match the directory names)
calibration_setup = "tau_autoconv_noneq"
# calibrate_to
calibrate_to = "Atlas_LES" # "Atlas_LES" or "Flight_Observations"
# SOCRATES setups
flight_numbers = [1,9,10,11,12,13]
# pad flight number to two digit string if is 1 digit
forcing_types  = [:obs_data]

experiment_dir = joinpath(pkg_dir, "experiments", "SOCRATES", "subexperiments", "SOCRATES_"*string(supersat_type))
# ========================================================================================================================= #
# tmax
# t_max = 14*3600.0 # 14 hours
# t_bnds = (;obs_data = missing, ERA5_data = missing) # normal full length
t_max = 7*3600.0 # shorter for testing (remember to change t_start, t_end, Σ_t_start, Σ_t_end in get_reference_config()# shorter for testing
t_bnds = (;obs_data = (t_max-2*3600.    , t_max), ERA5_data = (t_max-2*3600.     , t_max)) # shorter for testing
# ========================================================================================================================= #
# constants we use here
ρ_l = FT(1000.) # density of ice, default from ClimaParameters
ρ_i = FT(916.7) # density of ice, default from ClimaParameters
r_r = FT(20 * 1e-6) # 20 microns
r_0 = FT(.2 * 1e-6) # .2 micron base aerosol

N_l = FT(1e-5 / (4/3 * π * r_r^3 * ρ_l)) # estimated total N assuming reasonable q_liq.. (N = N_r in homogenous)
N_i = FT(1e-7 / (4/3 * π * r_r^3 * ρ_i)) # estimated total N assuming reasonable q_ice... (N = N_r + N_0)

D_ref = FT(0.0000226)
D = D_ref
# ========================================================================================================================= #
# setup stuff (needs to be here for ekp_par_calibration.sbatch to read), can read fine as long as is after "=" sign
N_ens  = 50 # number of ensemble members
N_iter = 15 # number of iterations
# ========================================================================================================================= #
bounded_edge_σ = FT(3.0) # is in log space go crazy (10 orders of magnitude is pretty big though)
calibration_parameters_default = Dict( # The variables we wish to calibrate , these aren't in the namelist so we gotta add them to the local namelist...
    #
    "geometric_liq_c_1"   => Dict("prior_mean" => FT(1/(4/3 * π * ρ_l * r_r^2))    , "constraints" => bounded_below(0) , "l2_reg" => nothing, "CLIMAParameters_longname" => nothing), 
    "geometric_liq_c_2"   => Dict("prior_mean" => FT(2/3.)                         , "constraints" => bounded(1/3., 1) , "l2_reg" => nothing, "CLIMAParameters_longname" => nothing), 
    "geometric_liq_c_3"   => Dict("prior_mean" => FT(N_l * r_0)                    , "constraints" => bounded_below(0) , "l2_reg" => nothing, "CLIMAParameters_longname" => nothing),  
    #
    "T_scaling_ice_c_1"   => Dict("prior_mean" => FT(10^-9) , "constraints" => bounded_below(0) , "l2_reg" => nothing, "CLIMAParameters_longname" => nothing, "unconstrained_σ" => 10.0), # normalizing factor has a pretty large range, 10^0 to 10^20 is realistic perhaps, a lot can be made up with the exponent c_2
    "T_scaling_ice_c_2"   => Dict("prior_mean" => FT(9) , "constraints" => bounded_below(0) , "l2_reg" => nothing, "CLIMAParameters_longname" => nothing, "unconstrained_σ" => 1.0), # exponent has small range 
    #
) # these aren't in the default_namelist so where should I put them?
calibration_parameters = deepcopy(calibration_parameters_default) # copy the default parameters and edit them below should we ever wish to change this

# global local_namelist = [] # i think if you use something like local_namelist = ... below inside the function it will just create a new local variable and not change this one, so we need to use global (i think we didnt need after switching to local_namelist_here but idk...)
local_namelist = [ # things in namelist that otherwise wouldn't be... (both random parameters and parameters we want to calibrate that we added ourselves that generate_namelist doesn't insert...)
    ("user_aux", "geometric_liq_c_1", calibration_parameters["geometric_liq_c_1"]["prior_mean"] ),
    ("user_aux", "geometric_liq_c_2", calibration_parameters["geometric_liq_c_2"]["prior_mean"] ),
    ("user_aux", "geometric_liq_c_3", calibration_parameters["geometric_liq_c_3"]["prior_mean"] ),
    #
    ("user_aux", "T_scaling_ice_c_1", calibration_parameters["T_scaling_ice_c_1"]["prior_mean"] ),
    ("user_aux", "T_scaling_ice_c_2", calibration_parameters["T_scaling_ice_c_2"]["prior_mean"] ),
    #
    # ("user_aux", "min_τ_liq", FT( 3.)), # stability testing
    # ("user_aux", "min_τ_ice", FT( 3.)), # stability testing
    #
    ("thermodynamics", "moisture_model", "nonequilibrium"), # choosing noneq for training...
    ("thermodynamics", "sgs", "mean"), # sgs has to be mean in noneq
    # ("user_args", (;use_supersat=supersat_type)), # we need supersat for non_eq results and the ramp for eq
    ("user_args", (;use_supersat=supersat_type, τ_use=:morrison_milbrandt_2015_style, sedimentation=true) ), # testing if this improves stability...

]
@info("local_namelist:", local_namelist)

calibration_vars = ["temperature_mean", "ql_mean", "qi_mean"]


# ========================================================================================================================= #
# ========================================================================================================================= #

obs_var_additional_uncertainty_factor = 0.1 # I hope this is in scaled space lmao... (so we'd be adding a variance of 1.0*obs_var value to the observation error variance), hope the mean is order 1 so the variance is reasonable...
obs_var_additional_uncertainty_factor = Dict( # I hope this is in scaled space lmao... (so we'd be adding a variance of 1.0*obs_var value to the observation error variance), hope the mean is order 1 so the variance is reasonable...
    "temperature_mean" => obs_var_additional_uncertainty_factor / 273, # scale down bc it's already so big for temperature, so divide by characteristic value to get ΔT ∼ obs_var_additional_uncertainty_factor instead... more like additive lol (note it's in normalized space but still)
    "ql_mean"          => obs_var_additional_uncertainty_factor,
    "qi_mean"          => obs_var_additional_uncertainty_factor,
)

# header_setup_choice = :simple # switch from :default to :simple calibration
header_setup_choice = :default # switch from :default to :simple calibration

alt_scheduler = DataMisfitController(on_terminate = "continue") # or just don't define it...

# alt_scheduler = :default # missing for use default, nothing for default eki timestepper w/ learning rate
# Δt = 8.0 # testing a larger one... (can also retry dmc since failures are reduced)

normalization_type = :pooled_nonzero_mean_to_value # let all variables have nonzero values mean 1, since we don't have a well defined variance or something to look at, and this way we can change our additional uncertainty factor freely

# ========================================================================================================================= #
# ========================================================================================================================= #

include(joinpath(main_experiment_dir, "Calibrate_and_Run_scripts", "calibrate", "config_calibrate_template_body.jl")) # load the template config file for the rest of operations


