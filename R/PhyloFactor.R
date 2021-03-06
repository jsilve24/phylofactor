#' Performs phylofactorization of a compositional dataset
#' @export
#' @param Data Data matrix whose rows are tip labels of the tree, columns are samples of the same length as X, and whose columns sum to 1
#' @param tree Phylogeny whose tip-labels are row-names in Data.
#' @param X independent variable.
#' @param frmla Formula for input in GLM. Default formula is Data ~ X
#' @param method Method for amalgamating groups and constructing basis. Default method = "ILR" uses the isometric log-ratio transform. Coming soon: method='add' which uses additive grouping with log-ratio regression.
#' @param choice Choice, or objective, function for determining the best edges at each iteration. Must be choice='var' or choice='F'. 'var' minimizes residual variance of clr-transformed data, whereas 'F' maximizes the F-statistic from an analysis of variance.
#' @param Grps Optional input of groups to be used in analysis to override the groups used in Tree. for correct format of groups, see output of getGroups
#' @param nfactors Number of clades or factors to produce in phylofactorization. Default, NULL, will iterate phylofactorization until either dim(Data)[1]-1 factors, or until stop.fcn returns T
#' @param stop.fcn Currently, accepts input of 'KS'. Coming soon: input your own function of the environment in phylofactor to determine when to stop.
#' @param stop.early Logical indicating if stop.fcn should be evaluated before (stop.early=T) or after (stop.early=F) choosing an edge maximizing the objective function.
#' @param ncores Number of cores for built-in parallelization of phylofactorization. Parallelizes the extraction of groups, amalgamation of data based on groups, regression, and calculation of objective function. Be warned - this can lead to R taking over a system's memory, so see clusterage for how to control the return of memory from clusters.
#' @param clusterage Age, i.e. number of iterations, for which a phyloFcluster should be used before returning its memory to the system. Default age=Inf - if having troubles with memory, consider a lower clusterage to return memory to system.
#' @param tolerance Tolerance for deviation of column sums of data from 1. if abs(colSums(Data)-1)>tolerance, a warning message will be displayed.
#' @param delta Numerical value for replacement of zeros. Default is 0.65, so zeros will be replaced with 0.65*min(Data[Data>0])
#' @return Phylofactor object, a list containing: "method", "Data", "tree" - inputs from phylofactorization. Output also includes "factors","glms","terminated" - T if stop.fcn terminated factorization, F otherwise - "atoms", "atom.sizes", "basis" - basis from "method" for projection of data onto phylofactors, and "Monophyletic.Clades" - a list of which atoms are monophyletic and have atom.size>1
#' @examples
#'  set.seed(1)
#'  library(ape)
#'  library(phangorn)
#'  library(compositions)
#'
#' tree <- unroot(rtree(7))

#' X <- as.factor(c(rep(0,5),rep(1,5)))
#' sigClades <- Descendants(tree,c(9,12),type='tips')
#' Data <- matrix(rlnorm(70,meanlog = 8,sdlog = .5),nrow=7)
#' rownames(Data) <- tree$tip.label
#' colnames(Data) <- X
#' Data[sigClades[[1]],X==0] <- Data[sigClades[[1]],X==0]*8
#' Data[sigClades[[2]],X==1] <- Data[sigClades[[2]],X==1]*9
#' Data <- t(clo(t(Data)))
#' Atoms <- atoms(G=sigClades,set=1:7)

#' PF <- PhyloFactor(Data,tree,X,nfactors=2)
#' PF$atoms
#' all(PF$atoms %in% Atoms)


PhyloFactor <- function(Data,tree,X,frmla = NULL,method='ILR',choice='var',Grps=NULL,nfactors=NULL,stop.fcn=NULL,stop.early=NULL,ncores=NULL,clusterage=Inf,tolerance=1e-10,delta=0.65,...){


  #### Housekeeping
  if (ncol(Data)!=length(X)){stop('number of columns of Data and length of X do not match')}
  if (typeof(Data) != 'double'){
    warning(' typeof(Data) is not "double" - will coerce with as.matrix(), but recommend using output $data for downstream analysis')
    Data <- as.matrix(Data)
    }
  if (all(rownames(Data) %in% tree$tip.label)==F){stop('some rownames of Data are not found in tree')}
  if (all(tree$tip.label %in% rownames(Data))==F){
    warning('some tips in tree are not found in dataset - output PF$tree will contain a trimmed tree')
    tree <- ape::drop.tip(tree,setdiff(tree$tip.label,rownames(Data)))}
  if (!all(rownames(Data)==tree$tip.label)){
    warning('rows of data are in different order of tree tip-labels - use output$data for downstream analysis, or set Data <- Data[tree$tip.label,]')
    Data <- Data[tree$tip.label,]
  }
  if (is.null(frmla)){frmla=Data ~ X}
  if (method %in% c('add','ILR')==F){stop('improper input method - must be either "add" or "multiply"')}
  if (choice %in% c('F','var')==F){stop('improper input "choice" - must be either "F" or "var"')}
  if(is.null(nfactors)){nfactors=Inf}
  if(ape::is.rooted(tree)){
    tree <- ape::unroot(tree)}

  #### Default treatment of Data ###
  if (any(Data==0)){
    if (delta==0.65){
      warning('Data has zeros and will receive default modification of zeros. Zeros will be replaced with delta*min(Data[Data>0]), default delta=0.65')
    }
    rplc <- function(x,delta){
      x[x==0]=min(x[x>0])*delta
      return(x)
    }

    Data <- apply(Data,MARGIN=2,FUN=rplc,delta=delta)

  }
  if (any(abs(colSums(Data)-1)>tolerance)){
    warning('Column Sums of Data are not sufficiently close to 1 - Data will be re-normalized by column sums')
    Data <- t(compositions::clo(t(Data)))

    if (any(abs(colSums(Data)-1)>tolerance)){
      warning('Attempt to divide Data by column sums did not bring column sums within "tolerance" of 1 - will proceed with factorization, but such numerical instability may affect the accuracy of the results')
    }
  }

 treeList <- list(tree)
 atomList <- list(1:ape::Ntip(tree))
 #### Get list of groups from tree ####
  if(is.null(Grps)){ #inputting groups allows us to make wrappers around PhyloFactor for efficient parallelization.
    Grps <- getGroups(tree)
  }
 # This is a list of 2-element lists containing the partitioning of tips
 # in our tree according to the edges. The groups can be mapped to the tree
 # via the node given names(Grps)[i]. The OTUs corresponding to the Groups can be found with:
 ### Get OTUs from tree
 OTUs <- tree$tip.label

 ################ OUTPUT ###################
 output <- NULL
 output$method <- method
 output$Data <- Data
 output$X <- X
 output$tree <- tree
 output$glms <- list()
 n <- length(tree$tip.label)

 if (is.null(stop.early) && is.null(stop.fcn)){
   STOP=F
 } else {
   STOP=T
 }

 if (is.null(stop.early)==F && is.null(stop.fcn)==T){
   stop.fcn='KS'
 }



 pfs=0
 age=0
 output$terminated=F
 cl=NULL

 while (pfs < min(length(OTUs)-1,nfactors)){


  if (is.null(ncores)==F && age==0){
    cl <- phyloFcluster(ncores)
  }


   if (pfs>=1){
     Data <- t(compositions::clo(t(Data/PhyloReg$residualData)))
     treeList <- updateTreeList(treeList,atomList,grp,tree)
     atomList <- updateAtomList(atomList,grp)
     Grps <- getNewGroups(tree,treeList,atomList)
   }

   ############# Perform Regression on all of Groups, and implement choice function ##############
   # clusterExport(cl,'pglm')
   # PhyloReg <- PhyloRegression(Data=Data,X=X,frmla=frmla,Grps=Grps,method=method,choice=choice,cl=cl)
   PhyloReg <- PhyloRegression(Data,X,frmla,Grps,method,choice,cl,...)
   ############################## EARLY STOP #####################################
   ###############################################################################

   age=age+1

   if (is.null(ncores)==F && age>=clusterage){
     parallel::stopCluster(cl)
     if (exists('cl') && is.null(cl)==F){
      rm(cl)
     }
     gc()
     age=0
   }

   if (STOP){
     if (is.null(stop.early)==T){
       if (is.null(stop.fcn)==F){
         if (stop.fcn=='KS'){
           ks <- ks.test(PhyloReg$p.values,runif(length(PhyloReg$p.values)))$p.value
           if (ks>0.01){
             output$terminated=T
             break
             }
         } else {
           stop.fcn(PhyloReg)
         }
       }
     }
   }

   ############# update output ########################
   winner <- PhyloReg$winner
   grp <- getLabelledGrp(winner,tree,Grps)
   grpInfo <- matrix(c(names(grp)),nrow=2)
   output$groups <- c(output$groups,list(Grps[[winner]]))
   output$factors <- cbind(output$factors,grpInfo)
   output$glms[[length(output$glms)+1]] <- PhyloReg$glm
   output$basis <- output$basis %>% cbind(PhyloReg$basis)
   if (choice=='var'){
     if (pfs==0){
       output$ExplainedVar <- PhyloReg$explainedvar
     } else {
       output$ExplainedVar <- c(output$ExplainedVar,(1-sum(output$ExplainedVar[1:pfs]))*PhyloReg$explainedvar)
     }
   }


   ############################## LATE STOP ######################################
   ############# Decide whether or not to stop based on PhyloReg #################
   if (STOP){
     if (is.null(stop.early)==F){
       if (is.null(stop.fcn)==F){
         if (stop.fcn=='KS'){
           ks <- ks.test(PhyloReg$p.values,runif(length(PhyloReg$p.values)))$p.value
           if (ks>0.01){
             output$terminated=T
             break
           }
         } else {
          stop.fcn(.GlobalEnv)
         }
       }
     }
   }

   pfs=pfs+1
 }




 ########### Clean up the Output ####################################
 if (is.null(output$factors)==F){
  pfs <- dim(output$factors)[2]
  colnames(output$factors)=sapply(as.list(1:pfs),FUN=function(a,b) paste(b,a,sep=' '),b='Factor',simplify=T)
  rownames(output$factors)=c('Group1','Group2')
 }
 output$atoms <- atoms(output$basis)
 NewOTUs <- output$atoms
 Monophyletic <- unlist(lapply(NewOTUs,function(x,y) return(ape::is.monophyletic(y,x)),y=tree))
 names(output$atoms)[Monophyletic] <- 'Monophyletic'
 names(output$atoms)[!Monophyletic] <- 'Paraphyletic'
 output$nfactors <- pfs
 output$factors <- t(output$factors)
 pvalues <- sapply(output$glms,FUN=function(gg) summary(aov(gg))[[1]][1,'Pr(>F)'])
 output$factors <- cbind(output$factors,pvalues)

 ### Make the atom size distribution data frame ###
 atomsize <- unlist(lapply(NewOTUs,FUN = length))
 ### The atoms are not all OTUs, but vary in size:
 sizes <- as.list(sort(unique(atomsize)))
 nsizes <- unlist(lapply(sizes,FUN=function(x,y){return(sum(y==x))},y=atomsize))
 output$atom.sizes <- data.frame('Atom Size'=unlist(sizes),'Number of Atoms'=nsizes)

 if (choice=='var'){
  names(output$ExplainedVar) <- sapply(as.list(1:pfs),FUN=function(a,b) paste(b,a,sep=' '),b='Factor',simplify=T)
 }



  output$Monophyletic.clades <- intersect(which(names(output$atoms)=='Monophyletic'),which(atomsize>1))

 if (is.null(ncores)==F && exists('cl')){  #shut down & clean out the cluster before exiting function
   parallel::stopCluster(cl)
   rm(cl)
   gc()
 }

 class(output) <- 'phylofactor'
 return(output)
}


