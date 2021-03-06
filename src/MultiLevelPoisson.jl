@inline near(I::CartesianIndex,a=0) = (2I-2oneunit(I)):(2I-oneunit(I)-δ(a,I))

@fastmath function restrictML(b::Array{Float64,m}) where m
    N = ntuple(i-> i==m ? m-1 : 1+size(b,i)÷2, m)
    a = zeros(N)
    @inbounds for i ∈ 1:m-1, I ∈ inside(N[1:m-1])
        a[I,i] = 0.5sum(b[J,i] for J ∈ near(I,i))
    end
    Poisson(a)
end

@fastmath restrict!(a::Array{Float64},b::Array{Float64}) = @inbounds @simd for I ∈ inside(a)
    a[I] = sum(@inbounds(b[J]) for J ∈ near(I))
end

prolongate!(a::Array{Float64},b::Array{Float64}) = @inbounds for I ∈ inside(b)
    @simd for J ∈ near(I)
        a[J] = b[I]
end;end

@inline divisible(N) = mod(N,2)==0 && N>4

struct MultiLevelPoisson{N,M} <: AbstractPoisson{N,M}
    levels :: Vector{Poisson{N,M}}
    function MultiLevelPoisson(L::Array{Float64,n}) where n
        levels = Vector{Poisson}()
        push!(levels,Poisson(L))
        while all(size(levels[end].x) .|> divisible)
            push!(levels,restrictML(levels[end].L))
        end
        text = "MultiLevelPoisson requires size=a2ⁿ, where a<10, n>1"
        @assert length(levels)>1 & all(size(levels[end].x).<10) text
        new{n,n-1}(levels)
    end
end

function Vcycle!(p::MultiLevelPoisson;l=1)
    # set up level l+1
    fill!(p.levels[l+1].x,0.)
    GS!(p.levels[l],it=0)
    restrict!(p.levels[l+1].r,p.levels[l].r)
    # solve l+1 (with recursion if possible)
    l+1<length(p.levels) && Vcycle!(p,l=l+1)
    GS!(p.levels[l+1],it=2)
    # correct level l
    prolongate!(p.levels[l].ϵ,p.levels[l+1].x)
    increment!(p.levels[l])
end

mult(p::MultiLevelPoisson,x) = mult(p.levels[1],x)

function solve!(x::Array{Float64,m},p::MultiLevelPoisson{n,m},b::Array{Float64,m};log=false,tol=1e-4,itmx=32) where {n,m}
    p.levels[1].x .= x
    residual!(p.levels[1],b); r₂ = L₂(p.levels[1].r)
    log && (res = [r₂])
    nᵖ=0
    while r₂>tol && nᵖ<itmx
        Vcycle!(p)
        GS!(p.levels[1],it=2); r₂ = L₂(p.levels[1].r)
        5tol>r₂>tol && (GS!(p.levels[1],it=1); r₂ = L₂(p.levels[1].r))
        log && push!(res,r₂)
        nᵖ+=1
    end
    x .= p.levels[1].x
    return log ? res : nᵖ
end
