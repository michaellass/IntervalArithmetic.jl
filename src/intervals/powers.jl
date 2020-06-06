
## Powers

struct PowerType{T} end

## Design:
# PowerType{:tight} gives tight powers of intervals using BigFloat
# PowerType{:fast} gives slightly less-tight but faster powers, using repeated multiplication (power_by_squaring), using the current directed rounding method

# CRlibm does not contain a correctly-rounded ^ function for Float64
# Use the BigFloat version from MPFR instead, which is correctly-rounded:
# Write explicitly like this to avoid ambiguity warnings:

for T in (:Integer, :Float64, :BigFloat, :Interval)
    @eval ^(::PowerType{:tight}, a::Interval{Float64}, x::$T) = atomic(Interval{Float64}, big53(a)^x)
end


# Integer power:

# overwrite new behaviour for small integer powers from
# https://github.com/JuliaLang/julia/pull/24240:

Base.literal_pow(::typeof(^), x::Interval{T}, ::Val{p}) where {T,p} = x^p


Base.eltype(x::Interval{T}) where {T<:Real} = T



function ^(::PowerType{:tight}, a::Interval{BigFloat}, n::Integer)
    isempty(a) && return a
    n == 0 && return one(a)
    n == 1 && return a
    # n == 2 && return sqr(a)
    n < 0 && a == zero(a) && return emptyinterval(a)

    T = BigFloat

    if isodd(n) # odd power
        isentire(a) && return a
        if n > 0
            a.lo == 0 && return @round(0, a.hi^n)
            a.hi == 0 && return @round(a.lo^n, 0)
            return @round(a.lo^n, a.hi^n)
        else
            if a.lo ≥ 0
                a.lo == 0 && return @round(a.hi^n, Inf)
                return @round(a.hi^n, a.lo^n)

            elseif a.hi ≤ 0
                a.hi == 0 && return @round(-Inf, a.lo^n)
                return @round(a.hi^n, a.lo^n)
            else
                return entireinterval(a)
            end
        end

    else # even power
        if n > 0
            if a.lo ≥ 0
                return @round(a.lo^n, a.hi^n)
            elseif a.hi ≤ 0
                return @round(a.hi^n, a.lo^n)
            else
                return @round(mig(a)^n, mag(a)^n)
            end

        else
            if a.lo ≥ 0
                return @round(a.hi^n, a.lo^n)
            elseif a.hi ≤ 0
                return @round(a.lo^n, a.hi^n)
            else
                return @round(mag(a)^n, mig(a)^n)
            end
        end
    end
end

function sqr(a::Interval{T}) where T<:Real
    return a^2
    # isempty(a) && return a
    # if a.lo ≥ zero(T)
    #     return @round(a.lo^2, a.hi^2)
    #
    # elseif a.hi ≤ zero(T)
    #     return @round(a.hi^2, a.lo^2)
    # end
    #
    # return @round(mig(a)^2, mag(a)^2)
end

^(a::Interval{BigFloat}, x::AbstractFloat) = a^big(x)

# Floating-point power of a BigFloat interval:
function ^(::PowerType{:tight}, a::Interval{BigFloat}, x::BigFloat)

    domain = Interval{BigFloat}(0, Inf)

    if a == zero(a)
        a = a ∩ domain
        x > zero(x) && return zero(a)
        return emptyinterval(a)
    end

    isinteger(x) && return a^(round(Int, x))
    x == 0.5 && return sqrt(a)

    a = a ∩ domain
    (isempty(x) || isempty(a)) && return emptyinterval(a)

    xx = atomic(Interval{BigFloat}, x)

    # @round() can't be used directly, because both arguments may
    # Inf or -Inf, which throws an error
    # lo = @round(a.lo^xx.lo, a.lo^xx.lo)
    lolod = @round_down(a.lo^xx.lo)
    lolou = @round_up(a.lo^xx.lo)
    lo = (lolod == Inf || lolou == -Inf) ?
        wideinterval(lolod) : Interval(lolod, lolou)

    # lo1 = @round(a.lo^xx.hi, a.lo^xx.hi)
    lohid = @round_down(a.lo^xx.hi)
    lohiu = @round_up(a.lo^xx.hi)
    lo1 = (lohid == Inf || lohiu == -Inf) ?
        wideinterval(lohid) : Interval(lohid, lohiu)

    # hi = @round(a.hi^xx.lo, a.hi^xx.lo)
    hilod = @round_down(a.hi^xx.lo)
    hilou = @round_up(a.hi^xx.lo)
    hi = (hilod == Inf || hilou == -Inf) ?
        wideinterval(hilod) : Interval(hilod, hilou)

    # hi1 = @round(a.hi^xx.hi, a.hi^xx.hi)
    hihid = @round_down(a.hi^xx.hi)
    hihiu = @round_up(a.hi^xx.hi)
    hi1 = (hihid == Inf || hihiu == -Inf) ?
        wideinterval(hihid) : Interval(hihid, hihiu)

    lo = hull(lo, lo1)
    hi = hull(hi, hi1)

    return hull(lo, hi)
end

function ^(a::Interval{Rational{T}}, x::AbstractFloat) where T<:Integer
    a = Interval(a.lo.num/a.lo.den, a.hi.num/a.hi.den)
    a = a^x
    atomic(Interval{Rational{T}}, a)
end

# Rational power
function ^(::PowerType{:tight}, a::Interval{T}, x::Rational) where T
    domain = Interval{T}(0, Inf)

    p = x.num
    q = x.den

    isempty(a) && return emptyinterval(a)
    x == 0 && return one(a)

    if a == zero(a)
        x > zero(x) && return zero(a)
        return emptyinterval(a)
    end

    x == (1//2) && return sqrt(a)

    if x >= 0
        if a.lo ≥ 0
            isinteger(x) && return a ^ Int64(x)
            a = @biginterval(a)
            ui = convert(Culong, q)
            low = BigFloat()
            high = BigFloat()
            ccall((:mpfr_rootn_ui, :libmpfr) , Int32 , (Ref{BigFloat}, Ref{BigFloat}, Culong, MPFRRoundingMode) , low , a.lo , ui, MPFRRoundDown)
            ccall((:mpfr_rootn_ui, :libmpfr) , Int32 , (Ref{BigFloat}, Ref{BigFloat}, Culong, MPFRRoundingMode) , high , a.hi , ui, MPFRRoundUp)
            b = interval(low, high)
            b = convert(Interval{T}, b)
            return b^p
        end

        if a.lo < 0 && a.hi ≥ 0
            isinteger(x) && return a ^ Int64(x)
            a = a ∩ Interval{T}(0, Inf)
            a = @biginterval(a)
            ui = convert(Culong, q)
            low = BigFloat()
            high = BigFloat()
            ccall((:mpfr_rootn_ui, :libmpfr) , Int32 , (Ref{BigFloat}, Ref{BigFloat}, Culong, MPFRRoundingMode) , low , a.lo , ui, MPFRRoundDown)
            ccall((:mpfr_rootn_ui, :libmpfr) , Int32 , (Ref{BigFloat}, Ref{BigFloat}, Culong, MPFRRoundingMode) , high , a.hi , ui, MPFRRoundUp)
            b = interval(low, high)
            b = convert(Interval{T}, b)
            return b^p
        end

        if a.hi < 0
            isinteger(x) && return a ^ Int64(x)
            return emptyinterval(a)
        end

    end

    if x < 0
        return inv(a^(-x))
    end

end

# Interval power of an interval:
function ^(::PowerType{:tight}, a::Interval{BigFloat}, x::Interval)
    T = BigFloat
    domain = Interval{T}(0, Inf)

    a = a ∩ domain

    (isempty(x) || isempty(a)) && return emptyinterval(a)

    lo1 = a^x.lo
    lo2 = a^x.hi
    lo1 = hull(lo1, lo2)

    hi1 = a^x.lo
    hi2 = a^x.hi
    hi1 = hull(hi1, hi2)

    hull(lo1, hi1)
end



"""
A fast (?) implementation of `x^n` using `power_by_squaring`.
Usually return an interval that is slightly larger than that calculated
using PowerType{:tight}, but is guaranteed to be a correct
enclosure when using multiplication with correct rounding.
"""
function ^(::PowerType{:fast}, x::Interval, n::Integer)  # fast integer power
    if n < 0
        return 1 / pow(x, -n)
    end

    isempty(x) && return x

    if iseven(n) && 0 ∈ x

        return hull(zero(x),
                    hull(Base.power_by_squaring(Interval(mig(x)), n),
                        Base.power_by_squaring(Interval(mag(x)), n))
            )

    else

      return hull( Base.power_by_squaring(Interval(x.lo), n),
                    Base.power_by_squaring(Interval(x.hi), n) )

    end

end

function pow(::PowerType{:fast}, x::Interval, y::Real)  # fast real power, including for y an Interval

    isempty(x) && return x
    isinteger(y) && return pow(x, Int(y.lo))
    return exp(y * log(x))

end
