using Base.Test

using ARCH
#=
Data from [1]. See [2] for a comparsion of GARCH software based on this data.
[1] Bollerslev, T. and Ghysels, E. (1996), Periodic Autoregressive Conditional Heteroscedasticity, Journal of Business and Economic Statistics (14), pp. 139-151. https://doi.org/10.2307/1392425
[2] Brooks, C., Burke, S. P., and Persand, G. (2001), Benchmarks and the accuracy of GARCH model estimation, International Journal of Forecasting (17), pp. 45-56. https://doi.org/10.1016/S0169-2070(00)00070-4
=#
#using HTTP
#res=HTTP.get("http://people.stern.nyu.edu/wgreene/Text/Edition7/TableF20-1.txt")
#r=convert.(Float64, readcsv(IOBuffer(res.body))[2:end])
T = 10^4;
@testset "GARCH" begin
    srand(1);
    spec = GARCH{1, 1}([1., .9, .05])
    am0 = simulate(spec, T);
    am00 = deepcopy(am0)
    srand(1)
    am00.data .= 0.
    simulate!(am00)
    @test all(am00.data .== am0.data)
    srand(1)
    am00 = simulate(am0)
    @test all(am00.data .== am0.data)
    am = selectmodel(GARCH, am0.data; meanspec=NoIntercept, show_trace=true)
    @test isfitted(am) == true
    @test all(isapprox.(coef(am), [0.9086632896184081,
                                   0.9055268468427705,
                                   0.050367854809777915], rtol=1e-4))
    @test all(isapprox.(stderror(am), [0.14582381264705224,
                                       0.010354562480367474,
                                       0.005222817398477784], rtol=1e-4))
    am2 = ARCHModel(spec, am0.data)
    @test isfitted(am2) == false
    io = IOBuffer()
    str = sprint(io -> show(io, am2))
    @test startswith(str, "\nGARCH{1,1}")
    fit!(am2)
    @test isfitted(am2) == true
    io = IOBuffer()
    str = sprint(io -> show(io, am2))
    @test startswith(str, "\nGARCH{1,1}")
    am3 = fit(am2)
    @test isfitted(am3) == true
    @test all(am2.spec.coefs .== am.spec.coefs)
    @test all(am3.spec.coefs .== am2.spec.coefs)
end

@testset "StatisticalModel" begin
    #not implemented: adjr2, deviance, mss, nulldeviance, r2, rss, weights
    srand(1);
    spec = GARCH{1, 1}([1., .9, .05])
    am = simulate(spec, T)
    fit!(am)
    @test loglikelihood(am) ==  ARCH.loglik!(Float64[],
                                                                Float64[],
                                                                Float64[],
                                                                typeof(spec),
                                                                StdNormal{Float64},
                                                                NoIntercept{Float64},
                                                                am.data,
                                                                spec.coefs
                                                                )
    @test nobs(am) == T
    @test dof(am) == 3
    @test coefnames(GARCH{1, 1}) == ["ω", "β₁", "α₁"]
    @test aic(am) ≈ 58369.082969298106 rtol=1e-4
    @test bic(am) ≈ 58390.713990414035 rtol=1e-4
    @test aicc(am) ≈ 58369.085370258494 rtol=1e-4
    @test all(coef(am) .== am.spec.coefs)
    @test all(isapprox(confint(am), [0.6228537382166024 1.1944723245606814;
                                    0.8852323068993577 0.9258214298904262;
                                    0.040131313548448275 0.060604377407810675],
                       rtol=1e-4)
                       )
    @test all(isapprox(informationmatrix(am; expected=false), [0.15326216336912968 2.9536982257433135 2.618124940552642;
                                                               2.9536982257433135 58.956837321202826 53.74888605159925;
                                                               2.618124940552642 53.74888605159925 53.29656483617587],
                       rtol=1e-4)
                       )
    @test_throws ErrorException informationmatrix(am)
    @test all(isapprox(score(am), [-4.091261171623728e-6 3.524550271549742e-5 -6.989366926291041e-5], rtol=1e-4))
    @test islinear(am::ARCHModel) == false
end

@testset "MeanSpecs" begin
    srand(1);
    spec = GARCH{1, 1}([1., .9, .05])
    am = simulate(spec, T; meanspec=Intercept(0.))
    fit!(am)
    @test all(isapprox(coef(am), [0.910496430719689,
                                   0.9054120402733519,
                                   0.05039127076312942,
                                   0.027705636765390795], rtol=1e-4))
    @test typeof(NoIntercept()) == NoIntercept{Float64}
end

@testset "ARCH" begin
    srand(1);
    spec = _ARCH{2}([1., .3, .4]);
    am = simulate(spec, T);
    @test selectmodel(_ARCH, am.data).spec.coefs == fit(_ARCH{2}, am.data).spec.coefs
end

@testset "EGARCH" begin
    srand(1)
    am = simulate(EGARCH{1, 1, 1}([.1, 0., .9, .1]), T; meanspec=Intercept(3))
    am7 = selectmodel(EGARCH, am.data; maxlags=2, show_trace=true)
    @test all(isapprox(coef(am7), [0.08502955535533116,
                                   0.004709708474515596,
                                   0.9164935566284109,
                                   0.09325947325535855,
                                   3.0137461089470308], rtol=1e-4))
    @test coefnames(EGARCH{2, 2, 2}) == ["ω", "γ₁", "γ₂", "β₁", "β₂", "α₁", "α₂"]
end

@testset "Errors" begin
    @test_warn "Fisher" stderror(ARCHModel(GARCH{3, 0}([1., .1, .2, .3]), [.1, .2, .3, .4, .5, .6, .7]))
    @test_warn "non-positive" stderror(ARCHModel(GARCH{3, 0}([1., .1, .2, .3]), -5*[.1, .2, .3, .4, .5, .6, .7]))
    e = @test_throws ARCH.NumParamError ARCH.loglik!(Float64[], Float64[], Float64[], GARCH{1, 1}, StdNormal{Float64},
                                                     NoIntercept{Float64}, zeros(T),
                                                     [0., 0., 0., 0.]
                                                     )
    str = sprint(showerror, e.value)
    @test startswith(str, "incorrect number of parameters")
    @test_throws ARCH.NumParamError GARCH{1, 1}([.1])
end

@testset "Distributions" begin
    @testset "Gaussian" begin
        srand(1)
        data = rand(T)
        @test typeof(StdNormal())==typeof(StdNormal(Float64[]))
        @test fit(StdNormal, data).coefs == Float64[]
        @test coefnames(StdNormal) == String[]
        @test ARCH.distname(StdNormal) == "Gaussian"
    end
    @testset "Student" begin
        srand(1)
        data = rand(StdTDist(4), 10000)
        spec = GARCH{1, 1}([1., .9, .05])
        @test fit(StdTDist, data).coefs[1] ≈ 3.972437329588246 rtol=1e-4
        @test coefnames(StdTDist) == ["ν"]
        @test ARCH.distname(StdTDist) == "Student's t"
        srand(1);
        datat = simulate(spec, T; dist=StdTDist(4)).data
        srand(1);
        datam = simulate(spec, T; dist=StdTDist(4), meanspec=Intercept(3)).data
        am4 = selectmodel(GARCH, datat; dist=StdTDist, meanspec=NoIntercept, show_trace=true)
        am5 = selectmodel(GARCH, datam; dist=StdTDist, show_trace=true)
        @test coefnames(am5) == ["ω", "β₁", "α₁", "ν", "μ"]
        @test all(coeftable(am4).cols[2] .== stderror(am4))
        @test all(isapprox(coef(am4), [0.8307014299672306,
                                       0.9189503152734588,
                                       0.042080807758329355,
                                       3.835646488238764], rtol=1e-4))

        @test all(isapprox(coef(am5), [0.8306175556436268,
                                       0.9189538270625667,
                                       0.04208964132482301,
                                       3.8348509665880797,
                                       2.9918445831618024], rtol=1e-4))
    end
end
