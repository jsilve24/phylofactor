% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/phyloregPar.R
\name{phyloregPar}
\alias{phyloregPar}
\title{Parallelized version of \code{\link{pglm}} for PhyloRegression}
\usage{
phyloregPar(Grps, Data, X, frmla, choice, method, Pbasis, cl, ...)
}
\arguments{
\item{Grps}{Groups over which to amalgamate Data & regress}

\item{Data}{Data matrix whose rows are parts and columns samples}

\item{X}{independent variable}

\item{frmla}{Formula for dependence of y on x}

\item{choice}{Method for choosing best group. choice='var' parallelizes computation of residual variance.}

\item{method}{method for amalgamating}

\item{Pbasis}{Coming soon...}

\item{cl}{phyloFcluster object. See \code{\link{phyloFcluster}}}
}
\value{
list of glm objects
}
\description{
Parallelized version of \code{\link{pglm}} for PhyloRegression
}
\examples{
set.seed(1)
tree <- unroot(rtree(7))
X <- as.factor(c(rep(0,5),rep(1,5)))
sigClades <- Descendants(tree,c(9,12),type='tips')
Data <- matrix(rlnorm(70,meanlog = 8,sdlog = .5),nrow=7)
rownames(Data) <- tree$tip.label
colnames(Data) <- X
Data[sigClades[[1]],X==0] <- Data[sigClades[[1]],X==0]*8
Data[sigClades[[2]],X==1] <- Data[sigClades[[2]],X==1]*9
Data <- t(clo(t(Data)))
Grps <- getGroups(tree)
frmla <- Data ~ X

cl <- phyloFcluster(2)
phyloregPar(Grps,Data,X,frmla,choice='var',method='ILR',Pbasis=1,cl=cl)
stopCluster(cl)
gc()
}

