#' Internal function for phyloregPar
#' @param Grps list of groups. see \code{\link{getGroups}}
#' @param Data data matrix. Rows are parts and columns are samples
#' @param XX independent variable
#' @param frmla formula for glm
#' @param n total number of taxa in Data
#' @param choice objective function allowing parallelization of residual variance calculations
#' @param method method for amalgamating groups
#' @param Pbasis coming soon
#' @param ... optional inputs for glm

phyreg <- function(Grps,Data=NULL,Y=NULL,XX,frmla,n,choice,method,Pbasis,...){
  #internal function for phyloregPar, using bigglm for memory-efficiency
  #input list of Groups, will output Y,GLMs, and, if choice=='var', residual variance.
  reg <- NULL
  if (is.null(Y)){
    reg$Y <- Grps %>% lapply(FUN=amalgamate,Data=Data,method)
  } else {
    reg$Y <- Y
  }

  GLMs <- reg$Y %>% lapply(FUN = pglm,x=XX,frmla=frmla,...)
  dataset <- model.frame(frmla,data=list('Data'=rep(0,length(XX)),'X'=XX))
  reg$Yhat <- lapply(GLMs,predict,newdata=dataset)
  if (!all(unlist(lapply(GLMs,FUN=function(bb){return(bb$converged)})))){warning('some bigGLMs did not converge. Try changing input argument maxit')}

  if(choice=='var'){
    # We need to predict the data matrix & calculate the residual variance.
    reg$residualvar <- rep(Inf,length(Grps))
    for (nn in 1:length(Grps)){
      prediction <- PredictAmalgam(reg$Yhat[[nn]],Grp=Grps[[nn]],n,method,Pbasis)
     reg$residualvar[nn] <- var(c(compositions::clr(t(Data))-compositions::clr(t(prediction))))
    }
    names(reg$residualvar) <- names(reg$Y)
     # reg$residualvar <- mapply(PredictAmalgam,reg$Yhat,Grps,n,method,Pbasis=Pbasis,SIMPLIFY=F) %>%
                            # sapply(.,FUN = residualVar,Data=Data)
  }

  # reg$GLMs <- GLMs #the GLMs from lapply(X=Y,FUN = phyloreg,x=XX,frmla=frmla,...) take up a lot of memory and have been removed.


  reg$stats <- mapply(GLMs,FUN=getStats,reg$Y) %>%
                  unlist %>%
                  matrix(.,,ncol=2,byrow=T) #contains Pvalues and F statistics
    rownames(reg$stats) <- names(reg$Y)
    colnames(reg$stats) <- c('Pval','F')

  return(reg)
}
