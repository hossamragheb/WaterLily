"""
    Poisson{N,M}

Composite type for conservative variable coefficient Poisson equations:

    ∮ds β ∂x/∂n = σ

The resulting linear system is

    Ax = [L+D+L']x = b

where A is symmetric, block-tridiagonal and extremely sparse. Implemented on a
structured grid of dimension M, then L has dimension N=M+1 and size(L,N)=M.
Moreover, D[I]=-∑ᵢ(L[I,i]+L'[I,i]). This means matrix storage, multiplication,
ect can be easily implemented and optimized without external libraries.

To help iteratively solve the system above, the Poisson structure holds
helper arrays for inv(D), the error ϵ=x̂=x, and residual r=b-Ax. An iterative
solution method then estimates the error ϵ=̃A⁻¹r and increments x+=ϵ, r-=Aϵ.
"""
abstract type AbstractPoisson{N,M} end
struct Poisson{N,M} <: AbstractPoisson{N,M}
    L :: Array{Float64,N} # Lower diagonal coefficients
    D :: Array{Float64,M} # Diagonal coefficients
    iD :: Array{Float64,M} # 1/Diagonal
    x :: Array{Float64,M} # approximate solution
    ϵ :: Array{Float64,M} # increment/error
    r :: Array{Float64,M} # residual
    function Poisson(L::Array{Float64,n}) where n
        N = size(L); M = N[1:end-1]; m = length(M)
        @assert N[end] == m
        x,ϵ,r,D,iD = zeros(M),zeros(M),zeros(M),zeros(M),zeros(M)
        @inbounds for I ∈ inside(M)
            D[I] = -sum(L[I,i]+L[I+δ(i,m),i] for i ∈ 1:m)
            iD[I] = abs2(D[I])<1e-8 ? 0. : inv(D[I])
        end
        new{n,m}(L,D,iD,x,ϵ,r)
    end
end

@fastmath @inline multL(I::CartesianIndex{d},L,x) where {d} =
    sum(@inbounds(x[I-δ(a,I)]*L[I,a]) for a ∈ 1:d)
@fastmath @inline multU(I::CartesianIndex{d},L,x) where {d} =
    sum(@inbounds(x[I+δ(a,I)]*L[I+δ(a,I),a]) for a ∈ 1:d)
@fastmath @inline mult(I,L,D,x) = @inbounds(x[I]*D[I])+multL(I,L,x)+multU(I,L,x)
function mult(p::Poisson{n,m},x::Array{Float64,m}) where {n,m}
    @assert size(p.x)==size(x)
    b = zeros(size(p.x))
    @inside b[I] = mult(I,p.L,p.D,x)
    return b
end

@fastmath residual!(p::Poisson,b::Array{Float64}) =
    @inside p.r[I] = b[I]-mult(I,p.L,p.D,p.x)

@fastmath increment!(p::Poisson) = @inbounds @simd for I ∈ inside(p.x)
    p.x[I] += p.ϵ[I]
    p.r[I] -= mult(I,p.L,p.D,p.ϵ)
end
"""
SOR!(p::Poisson;ω=1.5)

Successive Over Relaxation preconditioner. The routine uses backsubstitution
to compute ϵ=̃A⁻¹r, where ̃A=[D/ω+L], and then increments x,r.
"""
@fastmath function SOR!(p::Poisson{n,m}; ω=1.5) where {n,m}
    @inbounds for I ∈ inside(p.r) # order matters here
        σ = p.r[I]-multL(I,p.L,p.ϵ)
        p.ϵ[I] = ω*σ*p.iD[I]
    end
    increment!(p)
end
"""
GS!(p::Poisson;it=0)

Gauss-Sidel smoother. When it=0, the function serves as a Jacobi preconditioner.
"""
@fastmath function GS!(p::Poisson{n,m};it=0) where {n,m}
    @inside p.ϵ[I] = p.r[I]*p.iD[I]
    for i ∈ 1:it; @inbounds for I ∈ inside(p.r, reverse = i%2==0) # order matters here
        σ = p.r[I]-multL(I,p.L,p.ϵ)-multU(I,p.L,p.ϵ)
        p.ϵ[I] = σ*p.iD[I]
    end;end
    increment!(p)
end

function solve!(x::Array{Float64,m},p::Poisson{n,m},b::Array{Float64,m};log=false,tol=1e-4,itmx=1e3) where {n,m}
    p.x .= x
    residual!(p,b); r₂ = L₂(p.r)
    log && (res = [r₂])
    nᵖ=0
    while r₂>tol && nᵖ<itmx
        SOR!(p,ω=1.8); r₂ = L₂(p.r)
        log && push!(res,r₂)
        nᵖ+=1
    end
    x .= p.x
    return log ? res : nᵖ
end
