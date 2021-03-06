module WaterLily

include("util.jl")
export L₂,BC!,@inside,inside,δ

include("Poisson.jl")
export AbstractPoisson,Poisson,solve!,mult

include("MultiLevelPoisson.jl")
export MultiLevelPoisson,solve!,mult

include("Body.jl")
export BDIM_coef,BDIM_coef!

include("Flow.jl")
export Flow,mom_step!

end # module
