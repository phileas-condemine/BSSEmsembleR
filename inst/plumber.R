#* @apiTitle BSSEnsembleR
#* @apiDescription a plumber back-end for real-time ensemble modelling

# ---- GENERICS ------ #
isValidString<-function(x){
  !all(is.null(x) || is.na(x) || !is.atomic(x) || identical(x,"") || !is.character(x))
} #Done

OBID <- function(){ #Done
  ei <- as.hexmode(as.integer(Sys.time())) # 4-byte
  mi <- as.hexmode(6666666) #3-byte (I don't really care about the machine suplying this)
  pi <- as.hexmode(Sys.getpid()) # 2-byte
  ci <- as.hexmode(sample(1048576:16777215,1)) # 3-byte
  return(paste0(ei,mi,pi,ci))
}

assim <- function(exp,msg){
  a<-tryCatch(exp,error=function(e){a<-as.character(e)})
  if(!identical(a,T)){
    if(identical(a,F)){
      stop(paste0("Asserted that ",msg))
    }else{
      stop(paste0("Fail to asssert: ",msg,", cause: ",as.character(a)))
    }
  }
}

classNumber<-function(x){
  inherits(x,"numeric") || inherits(x,"integer")
}

# ----- FILTERS ------ #

#* @filter cors
cors <- function(res) { #Done
  res$setHeader("Access-Control-Allow-Origin", "*")
  plumber::forward()
} #Done

#* @filter tokenizer
tokenizer <-function(req){ #Done MUST BE VERIFIED
  body<-jsonlite::fromJSON(req$postBody)
  assertion<-getTokenValidation(body)
  if(assertion$Valid){
    plumber::forward()
  }else{
    out <- list(error = assertion$Message)
    res$status <- 404
    return(out)
  }
}

# ----- QUERIES ---- #
queryByID <- function(obid,field='_id'){
  q<-list(list("$oid" = unbox(obid)))
  names(q)<-field
  return(jsonlite::toJSON(q))
} # Done

queryByField<-function(obj,field){
  q<-list(unbox(obj))
  names(q)<-field
  return(jsonlite::toJSON(q))
} #Done Verified

queryByUsername<-function(username){ #Done
  out<-queryByField(username,"username")
  return(out)
} #Done Verified


# ----- GETTERS ---- #
getUserByUsername<-function(username){
  out<-.GlobalEnv$users$find(queryByUsername(username),'{}')
  return(out)
} #Done Verified

getUserByID<-function(userid){
  out<-.GlobalEnv$users$find(queryByID(userid),'{}')
  return(out)
} #Done Verified

getFileIDByObjectID<- function(col,obid){
  col$find(queryByID(obid),'{"file":1,"_id":0}')$file
} #Done

getFileGridFS <- function(grid,fileID){
  t <- tempfile()
  out <- grid$read(paste0("id:", fileID),t, progress = FALSE)
  return(t)
} #Done

# -- HELPERS -- #

createNewUser<-function(username,password){
  id<-OBID()
  hash<-bcrypt::hashpw(password)
  .GlobalEnv$users$insert(jsonlite::toJSON(list("_id"=list("$oid" = jsonlite::unbox(id)),"username"=username,"hash"=hash)))
  out<-list("_id"=id,"username"=username,"hash"=hash)
  return(out)
} #Done #Verified

authorizeUser<-function(user,password){
  nrow(user) == 1 && isValidString(user$hash[[1]]) && bcrypt::checkpw(password, user$hash[[1]])
} #Done #Verified

authorizeToken<-function(user,token){
  nrow(user) == 1 && bcrypt::checkpw(user$hash[[1]],token)
}#Done verified

registerUserFile <- function(col,userid,fileid){#Done
  obid <- OBID()
  q<-list(list("$oid" = unbox(obid)),list("$oid" = unbox(userid)),list("$oid" = unbox(fileid)))
  names(q)<-c("_id","user","file")
  data<-jsonlite::toJSON(q)
  col$insert(data)
  return(obid)
}

# -- VALIDATIONs -- #

getRegistrationValidation <- function(body) {
  tryCatch({
    assim({isValidString(body$username) == T},"username is not valid.")
    assim({isValidString(body$password) == T},"passord is not valid")
    assim({isValidString(body$validation) == T},"password confirmation is not valid.")
    assim({body$password == body$validation},"passwords don't match.")
    assim({body$invitation == .GlobalEnv$BSSEInvitation},"invitation key don't match.")
    assim({length(getUserByUsername(body$username)) == 0},"username already exists.")
    out <- list(Valid = T, Message = '')
    return(out)
  }, error = function(e) {
    out <- list(Valid = F, Message = e)
    return(out)
  })
} #Done Verified

getLoginValidation <- function(body) {
  tryCatch({
    assim({isValidString(body$username)},'username is invalid.')
    assim({isValidString(body$password)},'password is invalid.')
    user<-getUserByUsername(body$username);
    assim({authorizeUser(user,body$password)},'username does not exist or password is wrong.')

    out <- list(Valid = T, Message = '')
    return(out)
  }, error = function(e) {
    out <- list(Valid = F, Message = as.character(e))
    return(out)
  })
} #Done Verified

getTokenValidation<-function(body){
  tryCatch({
  assim({isValidString(body$userid)},'userid is missing, token is invalid.')
  assim({isValidString(body$token)},'token is invalid.')
  user <- getUserByID(body$userid)
  assim({authorizeToken(user,body$token)},'token is invalid.')
  out <- list(Valid = T, Message = '')
  return(out)
  }, error = function(e) {
    out <- list(Valid = F, Message = as.character(e))
    return(out)
  })
} # Done verified

getDatasetValidation <- function(file){

  tryCatch({

  load(file)
  X<-as.data.frame(X)
  Y<-as.data.frame(Y)

  #X Validation
  assim({ncol(X)>2},paste0('X has insufficient number of predictors inputs:',as.character(ncol(X))))
  assim({nrow(X)>0},paste0('X has insufficient number of observations:',as.character(nrow(X))))
  assim({is.integer(X[,1])},paste0('Firts column of X is class ',class(X[,1]),', and not integer class.'))
  assim({is.factor(X[,2])},paste0('Second column of X is class ',class(X[,2]),', and not factor class.'))
  assim({all(sapply(X[,3:ncol(X)], classNumber))},'All supplied predictors inputs, except for column one and two, should be of integer or numeric class.')

  #Y validation
  assim({ncol(Y)>0},paste0('Y has insufficient number of predictors outputs:',as.character(ncol(Y))))
  assim({nrow(Y)>0},paste0('Y has insufficient number of observations:',as.character(nrow(Y))))
  assim({classNumber(Y[,1])},'The Supplied predictor output should be of integer or numeric class.')

  #mutual validation
  assim({nrow(X)==nrow(Y)},paste0('X number of observations (',as.character(nrow(X)),') differs from Y (',as.character(nrow(Y)),').'))
  assim({sum((complete.cases(X) & complete.cases(Y)))>0},'X and Y have independent number of NA or null observations.')
  out <- list(Valid = T, Message = '')
  return(out)
  }, error = function(e) {
    out <- list(Valid = F, Message = as.character(e))
    return(out)
  })

} #Done

# -- AUTHENTICATION -- #

#* Allow user to validate in server creating a user document (passwords should not be stored in the database)
#* @preempt tokenizer
#* @post /register
function(req, res) {
  body <- jsonlite::fromJSON(req$postBody)
  assertion <- getRegistrationValidation(body)
  if (assertion$Valid) {
    newuser <- createNewUser(body$username, body$password)
    out <- list(userid = newuser$'_id' ,token = bcrypt::hashpw(newuser$'hash'))
    res$status <- 202
    return(out)
  } else{
    out <- list(error = assertion$Message)
    res$status <- 404
    return(out)
  }
} #Done Verified

#* Initial login validation
#* @preempt tokenizer
#* @post /login
function(req, res) {
  body <- jsonlite::fromJSON(req$postBody)
  assertion <- getLoginValidation(body)
  if (assertion$Valid) {
    user <- getUserByUsername(body$username)
    out <-
      list(userid = user$"_id",
           token = bcrypt::hashpw(user$hash[[1]]))
    res$status <- 202
    return(out)
  } else{
    out <- list(error = assertion$Message)
    res$status <- 404
    return(out)
  }
} #Done Verified




# -------------------------------------------------- DATASET ---------------------------------------------------------- #

# -- Available -- #

#* Get list of available datasets for a user
#* @post /datasets/available
function(req,res){
  body<-jsonlite::fromJSON(req$postBody)
  query<-queryByID(body$userid, field="user")
  fields<-'{"_id":1}'
  return(.GlobalEnv$datasets$find(query,fields)$'_id')
} #Done Verified

# -- Load -- #

#* Loads dataset file in BSSEmsembler
#* @preempt tokenizer
#* @param userid
#* @param token
#* @post /datasets/load
function(req,userid,token){
  val<-getTokenValidation(list('userid'=userid,'token'=token))
  if(val$Valid){
    fileid <- MultipartDataset2GridFS(req)
    obid<-registerUserFile(.GlobalEnv$datasets,userid,fileid)
    return(obid)
  }else{
    stop(val$Message)
  }
} #Done

MultipartDataset2GridFS <- function(req){
  form <- Rook::Multipart$parse(req)
  assim({grepl(".RData",form$file$filename)},"Input file is not a valid .RData file.")
  val<-getDatasetValidation(form$file$tempfile)
  if(val$Valid){
    upload <-.GlobalEnv$gridFS$write(form$file$tempfile,form$file$filename)
    return(upload$id)
  }else{
    stop(val$Message)
  }
}



#-- Delete -- #
#* Gets dataset information in BSSEmsembler
#* @post /datasets/delete
function(req){
  body <- jsonlite::fromJSON(req$postBody)
  .GlobalEnv$datasets$remove(queryByID(body$datasetid), just_one = TRUE)
  .GlobalEnv$gridFS$remove(body$datasetid)
}


#-- Info -- #
#* Gets dataset information in BSSEmsembler
#* @post /datasets/info
function(datasetid){
  body <- jsonlite::fromJSON(req$postBody)
  fileid <- getFileIDByObjectID(.GlobalEnv$datasets,body$datasetid)#done
  file <- getFileGridFS(.GlobalEnv$gridFS, fileid)
  met<-getFileMetaInfo(fileid) #done
  sum<-getDatasetSummary(file) #done
  val<-getDatasetValidation(file) #done
  pls<-getDatasetPlots(file)
  unlink(file)
  return(list('Meta'=met,'Summary'=sum,'Validation'=val,'Plots'=pls))
}

getDatasetSummary <- function(file){

  XSummary <- NULL
  XBatchSummary <- NULL
  YSummary <- NULL
  YBatchSummary <- NULL

  tryDo({load(file)})
  tryDo(X<-as.data.frame(X))
  tryDo(Y<-as.data.frame(Y))
  tryDo({XSummary<-getHtmlSummary(X)})
  tryDo({XBatchSummary<-getHtmlBatchSummary(X,X[,2])})
  tryDo({YSummary<-getHtmlSummary(Y)})
  tryDo({YSummary<-getHtmlBatchSummary(Y,X[,2])})
  lst<-list(XSummary,XBatchSummary,YSummary,YBatchSummary)
  names(lst)<-c('XSummary','XBatchSummary','YSummary','YBatchSummary')
  return(lst)
}
getHtmlSummary <- function(df){
  st<- summarytools::dfSummary(df, round.digits = 3)
  stv<- summarytools::view(st,method='render',transpose =T,style="rmarkdown")
  html<- htmltools::renderTags(stv)$html
  return(html)
}
getHtmlDescriptive <-function(df){
  st<- summarytools::descr(df)
  stv<- summarytools::view(st,method='render',transpose =T,style="rmarkdown")
  return( htmltools::renderTags(stv)$html)
}
getHtmlBatchSummary <-function(df,cla){
  lapply(split(df,cla),getHtmlDescriptive)
}


getFileMetaInfo<-function(fileid){
  .GlobalEnv$gridFS$find(queryByID(fileid),'{}')
}
getDatasetPlots<-function(file){

}









