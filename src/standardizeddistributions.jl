struct StdNormal{T} <: StandardizedDistribution{T}
    coefs::Vector{T}
    StdNormal{T}() where {T} = new{T}(T[])
end
StdNormal(T::Type=Float64) = StdNormal{T}()
rand(::StdNormal{T}) where {T} = randn(T)
@inline logkernel(::Type{<:StdNormal}, x, coefs) = -abs2(x)/2
@inline logconst(::Type{<:StdNormal}, coefs)  =  -log2π/2
nparams(::Type{<:StdNormal}) = 0
coefnames(::Type{<:StdNormal}) = String[]
distname(::Type{<:StdNormal}) = "Gaussian"

function constraints(::Type{<:StdNormal}, ::Type{T})  where {T<:AbstractFloat}
    lower = T[]
    upper = T[]
    return lower, upper
end

function startingvals(::Type{<:StdNormal}, data::Vector{T})  where {T<:AbstractFloat}
    return T[]
end

struct StdTDist{T} <: StandardizedDistribution{T}
    coefs::Vector{T}
    StdTDist{T}(ν::T) where {T} = (ν>2 ? new{T}([ν]) : error("degrees of freedom must be greater than 2."))
end
StdTDist(ν::T) where {T} = StdTDist{T}(ν)
StdTDist(ν::Integer) = StdTDist(float(ν))
(rand(d::StdTDist{T})::T) where {T}  =  (ν=d.coefs[1]; tdistrand(ν)*sqrt((ν-2)/ν))
@inline logkernel(::Type{<:StdTDist}, x, coefs) = (-(coefs[1] + 1) / 2) * log1p(abs2(x) / (coefs[1]-2))
@inline logconst(::Type{<:StdTDist}, coefs)  =  lgamma((coefs[1] + 1) / 2) - log((coefs[1]-2) * pi) / 2 - lgamma(coefs[1] / 2)
nparams(::Type{<:StdTDist}) = 1
coefnames(::Type{<:StdTDist}) = ["ν"]
distname(::Type{<:StdTDist}) = "Student's t"

function constraints(::Type{<:StdTDist}, ::Type{T}) where {T}
    lower = T[20/10]
    upper = T[Inf]
    return lower, upper
end

function startingvals(::Type{<:StdTDist}, data::Array{T}) where {T}
    #mean of abs(t)
    eabst(ν)=2*sqrt(ν-2)/(ν-1)/beta(ν/2, 1/2)
    ##alteratively, could use mean of log(abs(t)):
    #elogabst(ν)=log(ν-2)/2-digamma(ν/2)/2+digamma(1/2)/2
    ht = zeros(data)
    loglik!(ht, GARCH{1, 1}, StdNormal, data, startingvals(GARCH{1, 1}, data))
    lower = convert(T, 2)
    upper = convert(T, 30)
    z = mean(abs.(data)./sqrt.(ht))
    z > eabst(upper) ? [upper] : [find_zero(x->z-eabst(x), (lower, upper))]
end
