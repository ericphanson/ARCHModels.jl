__precompile__()
#Todo:
#docs
#pretty print output by overloading show
#plotting via timeseries
#marketdata
#alternative error distributions
#standard errors
#demean?

#test new constructors and fit(!) methods
#how to export arch?
#what should simulate return?


module ARCH

using StatsBase: StatisticalModel
using Optim
using Base.Cartesian: @nloops, @nref, @ntuple
import StatsBase: loglikelihood, nobs, fit, aic, bic, aicc, dof, coef, coefnames
export            loglikelihood, nobs, fit, aic, bic, aicc, dof, coef, coefnames
export ARCHModel, VolatilitySpec, simulate, selectmodel

abstract type VolatilitySpec end

struct NumParamError <: Exception
    expected::Int
    got::Int
end

Base.showerror(io::IO, e::NumParamError) = print(io, "incorrect number of parameters: expected $(e.expected), got $(e.got).")

struct ARCHModel{VS<:VolatilitySpec, T<:AbstractFloat} <: StatisticalModel
    data::Vector{T}
    ht::Vector{T}
    coefs::Vector{T}
    function ARCHModel{VS, T}(data, ht, coefs) where {VS, T}
        length(coefs) == nparams(VS)  || throw(NumParamError(nparams(VS), length(coefs)))
        new(data, ht, coefs)
    end
end
ARCHModel(::Type{VS}, data::Vector{T}, ht::Vector{T}, coefs::Vector{T}) where {VS<:VolatilitySpec, T} = ARCHModel{VS, T}(data, ht, coefs)
ARCHModel(::Type{VS}, data, coefs) where {VS<:VolatilitySpec} = (ht = zeros(data); loglik!(ht, VS, data, coefs); ARCHModel(VS, data, ht, coefs))

loglikelihood(am::ARCHModel{VS}) where {VS<:VolatilitySpec} = loglik!(zeros(am.data), VS, am.data, am.coefs)
nobs(am::ARCHModel) = length(am.data)
dof(am::ARCHModel{VS}) where {VS<:VolatilitySpec} = nparams(VS)
coef(am::ARCHModel)=am.coefs
coefnames(::ARCHModel{VS}) where {VS<:VolatilitySpec} = coefnames(VS)

function simulate(::Type{VS}, nobs, coefs::Vector{T}) where {VS<:VolatilitySpec, T<:AbstractFloat}
    const warmup = 100
    data = zeros(T, nobs+warmup)
    ht = zeros(T, nobs+warmup)
    sim!(ht, VS, data, coefs)
    data[warmup+1:warmup+nobs]
end

function loglik!(ht::Vector{T1}, ::Type{VS}, data::Vector{T1}, coefs::Vector{T1}) where {VS<:VolatilitySpec, T1<:AbstractFloat}
    T = length(data)
    r = presample(VS)
    length(coefs) == nparams(VS) || throw(NumParamError(nparams(VS), length(coefs)))
    T > r || error("Sample too small.")
    log2pi = T1(1.837877066409345483560659472811235279722794947275566825634303080965531391854519)
    @inbounds begin
        h0 = uncond(VS, coefs)
        h0 > 0 || return T1(NaN)
        lh0 = log(h0)
        ht[1:r] .= h0
        LL = r*lh0+sum(data[1:r].^2)/h0
        @fastmath for t = r+1:T
            update!(ht, VS, data, coefs, t)
            LL += log(ht[t]) + data[t]^2/ht[t]
        end#for
    end#inbounds
    LL = -(T*log2pi+LL)/2
end#function


function sim!(ht::Vector{T1}, ::Type{VS}, data::Vector{T1}, coefs::Vector{T1}) where {VS<:VolatilitySpec, T1<:AbstractFloat}
    T =  length(data)
    r = presample(VS)
    length(coefs) == nparams(VS) || throw(NumParamError(nparams(VS), length(coefs)))
    @inbounds begin
        h0 = uncond(VS, coefs)
        h0 > 0 || error("Model is nonstationary.")
        randn!(@view data[1:r])
        data[1:r] .*= sqrt(h0)
        @fastmath for t = r+1:T
            update!(ht, VS, data, coefs, t)
            data[t] = sqrt(ht[t])*randn(T1)
        end
    end
    return nothing
end

function fit!(ht::Vector{T}, coefs::Vector{T}, ::Type{VS}, data::Vector{T}, algorithm=BFGS; kwargs...) where {VS<:VolatilitySpec, T<:AbstractFloat}
    obj = x -> -loglik!(ht, VS, data, x)
    lower, upper = constraints(VS, T)
    res = optimize(obj, coefs, lower, upper, Fminbox{algorithm}(); kwargs...)
    coefs .= res.minimizer
    return nothing
end
fit!(AM::ARCHModel{VS}, algorithm=BFGS; kwargs...) where {VS<:VolatilitySpec} = fit!(AM.ht, AM.coefs, VS, AM.data, algorithm; kwargs...)
fit(::Type{VS}, data, algorithm=BFGS; kwargs...) where VS<:VolatilitySpec = (ht = zeros(data); coefs=startingvals(VS, data); fit!(ht, coefs, VS, data, algorithm; kwargs...); return ARCHModel(VS, data, ht, coefs))
fit(AM::ARCHModel{VS}, algorithm=BFGS; kwargs...) where {VS<:VolatilitySpec} = (AM2=ARCHModel(VS, AM.data, AM.coefs); fit!(AM2, algorithm=BFGS; kwargs...); return AM2)



function selectmodel(::Type{VS}, data::Vector{T}, maxpq=3, args...; criterion=bic, kwargs...) where {VS<:VolatilitySpec, T<:AbstractFloat}
    #ndims = length(Base.unwrap_unionall(VS).parameters) #e.g., two (p and q) for GARCH{p, q}
    ndims =my_unwrap_unionall(VS)#e.g., two (p and q) for GARCH{p, q}
    res = _selectmodel(VS, Val{ndims}(), Val{maxpq}(), data)
    crits = criterion.(res)
    _, ind = findmin(crits)
    return res[ind]
end

@generated function _selectmodel(VS, ::Val{ndims}, ::Val{maxpq}, data) where {ndims, maxpq}
    quote
        res =Array{ARCHModel, $ndims}(@ntuple($ndims, i->$maxpq))
        @nloops $ndims i res begin
        @nref($ndims, res, i) = fit(VS{@ntuple($ndims, i)...}, data)
    end
    return res
end
end

#count the number of type vars. there's probably a better way.
function my_unwrap_unionall(a::ANY)
    count=0
    while isa(a, UnionAll)
        a = a.body
        count += 1
    end
    return count
end
include("GARCH.jl")
end#module
