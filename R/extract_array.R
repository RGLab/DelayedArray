### =========================================================================
### extract_array()
### -------------------------------------------------------------------------
###


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Low-level helpers
###

### Return the slice as a list.
.extract_data_frame_slice <- function(x, index)
{
    slice <- subset_by_Nindex(x, index)
    ## Turn into a list and replace factors with character vectors.
    lapply(slice, as.vector)
}
.extract_DataFrame_slice <- function(x, index)
{
    slice <- subset_by_Nindex(x, index)
    slice <- as.data.frame(slice)
    ## Turn into a list and replace factors with character vectors.
    lapply(slice, as.vector)
}

### Return a list with one list element per column in data frame 'x'.
### All the list elements have length 0.
.extract_data_frame_slice0 <- function(x)
{
    slice0 <- x[0L, , drop=FALSE]
    ## Turn into a list and replace factors with character vectors.
    lapply(slice0, as.vector)
}
.extract_DataFrame_slice0 <- function(x)
{
    slice0 <- x[0L, , drop=FALSE]
    slice0 <- as.data.frame(slice0)
    if (ncol(slice0) != ncol(x))
        stop(wmsg("DataFrame object 'x' can be used as the seed of ",
                  "a DelayedArray object only if as.data.frame(x) ",
                  "preserves the number of columns"))
    ## Turn into a list and replace factors with character vectors.
    lapply(slice0, as.vector)
}

### Equivalent to 'typeof(as.matrix(x))' but with an almost-zero
### memory footprint (it avoids the cost of turning 'x' into a matrix).
.get_data_frame_type <- function(x)
{
    if (ncol(x) == 0L)
        return("logical")
    slice0 <- .extract_data_frame_slice0(x)
    typeof(unlist(slice0, use.names=FALSE))
}

### Equivalent to 'typeof(as.matrix(as.data.frame(x)))' but with an
### almost-zero memory footprint (it avoids the cost of turning 'x' first
### into a data frame then into a matrix).
.get_DataFrame_type <- function(x)
{
    if (ncol(x) == 0L)
        return("logical")
    slice0 <- .extract_DataFrame_slice0(x)
    typeof(unlist(slice0, use.names=FALSE))
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### extract_array() generic and methods
###

.contact_author_msg <- function(Class)
{
    msg <- c("Please contact the author of the ", Class, " class")
    class_package <- attr(Class, "package")
    if (!is.null(class_package))
        msg <- c(msg, " (defined in the ", class_package, " package)")
    c(msg, " about this and point him/her to the man page for ",
           "extract_array() in the DelayedArray package (?extract_array).")
}

### 'index' is expected to be an unnamed list of subscripts as positive
### integer vectors, one vector per dimension in 'x'. *Missing* list elements
### are allowed and represented by NULLs.
### The "extract_array" methods don't need to support anything else.
### They must return an ordinary array. No need to propagate the dimnames.
setGeneric("extract_array", signature="x",
    function(x, index)
    {
        x_dim <- dim(x)
        if (is.null(x_dim))
            stop(wmsg("first argument to extract_array() must have dimensions"))
        ans <- standardGeneric("extract_array")
        if (!is.array(ans))
            stop(wmsg("The \"extract_array\" method for ", class(x), " ",
                      "objects didn't return an ordinary array. ",
                      "extract_array() should always return an ordinary ",
                      "array. ", .contact_author_msg(class(x))))
        expected_dim <- get_Nindex_lengths(index, x_dim)
        if (!identical(dim(ans), expected_dim))
            stop(wmsg("The \"extract_array\" method for ", class(x), " ",
                      "objects returned an array with incorrect ",
                      "dimensions. ", .contact_author_msg(class(x))))
        ans
    }
)

setMethod("extract_array", "ANY",
    function(x, index)
    {
        slice <- subset_by_Nindex(x, index)
        as.array(slice)
    }
)

setMethod("extract_array", "array",
    function(x, index) subset_by_Nindex(x, index)
)

### Equivalent to
###
###     subset_by_Nindex(as.matrix(x), index)
###
### but avoids the cost of turning the full data frame 'x' into a matrix so
### memory footprint stays small when 'index' is small.
setMethod("extract_array", "data.frame",
    function(x, index)
    {
        #ans_type <- .get_data_frame_type(x)
        slice0 <- .extract_data_frame_slice0(x)
        slice <- .extract_data_frame_slice(x, index)
        data <- unlist(c(slice0, slice), use.names=FALSE)
        array(data, dim=get_Nindex_lengths(index, dim(x)))
    }
)

### Equivalent to
###
###     subset_by_Nindex(as.matrix(as.data.frame(x)), index)
###
### but avoids the cost of turning the full DataFrame 'x' first into a data
### frame then into a matrix so memory footprint stays small when 'index' is
### small.
setMethod("extract_array", "DataFrame",
    function(x, index)
    {
        #ans_type <- .get_DataFrame_type(x)
        slice0 <- .extract_DataFrame_slice0(x)
        slice <- .extract_DataFrame_slice(x, index)
        data <- unlist(c(slice0, slice), use.names=FALSE)
        array(data, dim=get_Nindex_lengths(index, dim(x)))
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### type() generic and default method
###

### Conflicts with Biostrings::type!
setGeneric("type", function(x) standardGeneric("type"))

setMethod("type", "array", function(x) typeof(x))

### type() works out-of-the-box on any array-like object for which
### extract_array() works.
setMethod("type", "ANY",
    function(x)
    {
        x_dim <- dim(x)
        if (is.null(x_dim))
            stop(wmsg("type() only supports array-like objects. ",
                      "See ?type in the DelayedArray package."))
        ## x0 <- x[integer(0), ..., integer(0)]
        index <- rep.int(list(integer(0)), length(x_dim))
        x0 <- extract_array(x, index)
        type(x0)
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### as.array(x) (in-memory realization of an array-like object)
###

### TODO: Do we actually need this? Using drop() should do it.
.reduce_array_dimensions <- function(x)
{
    x_dim <- dim(x)
    x_dimnames <- dimnames(x)
    effdim_idx <- which(x_dim != 1L)  # index of effective dimensions
    if (length(effdim_idx) >= 2L) {
        x <- set_dim(x, x_dim[effdim_idx])
        x <- set_dimnames(x, x_dimnames[effdim_idx])
    } else {
        x <- set_dim(x, NULL)
        if (length(effdim_idx) == 1L)
            names(x) <- x_dimnames[[effdim_idx]]
    }
    x
}

### Realize the object i.e. execute all the delayed operations and turn the
### object back into an ordinary array.
.from_Array_to_array <- function(x, drop=FALSE)
{
    if (!isTRUEorFALSE(drop))
        stop("'drop' must be TRUE or FALSE")
    index <- rep.int(list(NULL), length(dim(x)))
    ans <- extract_array(x, index)
    ans <- set_dimnames(ans, dimnames(x))
    if (drop)
        ans <- .reduce_array_dimensions(ans)
    ans
}

### S3/S4 combo for as.array.Array
as.array.Array <- function(x, ...) .from_Array_to_array(x, ...)
setMethod("as.array", "Array", .from_Array_to_array)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Other coercions to in-memory representations
###
### All these coercions are based on as.array().
###

.SLICING_TIP <- c(
    "Consider reducing its number of effective dimensions by slicing it ",
    "first (e.g. x[8, 30, , 2, ]). Make sure that all the indices used for ",
    "the slicing have length 1 except at most 2 of them which can be of ",
    "arbitrary length or missing."
)

.from_Array_to_matrix <- function(x)
{
    x_dim <- dim(x)
    if (sum(x_dim != 1L) > 2L)
        stop(wmsg(class(x), " object with more than 2 effective dimensions ",
                  "cannot be coerced to a matrix. ", .SLICING_TIP))
    ans <- as.array(x, drop=TRUE)
    if (length(x_dim) == 2L) {
        ans <- set_dim(ans, x_dim)
        ans <- set_dimnames(ans, dimnames(x))
    } else {
        as.matrix(ans)
    }
    ans
}

### S3/S4 combo for as.matrix.Array
as.matrix.Array <- function(x, ...) .from_Array_to_matrix(x, ...)
setMethod("as.matrix", "Array", .from_Array_to_matrix)

### S3/S4 combo for as.data.frame.Array
as.data.frame.Array <- function(x, row.names=NULL, optional=FALSE, ...)
    as.data.frame(as.array(x, drop=TRUE),
                  row.names=row.names, optional=optional, ...)
setMethod("as.data.frame", "Array", as.data.frame.Array)

### S3/S4 combo for as.vector.Array
as.vector.Array <- function(x, mode="any")
{
    ans <- as.array(x, drop=TRUE)
    as.vector(ans, mode=mode)
}
setMethod("as.vector", "Array", as.vector.Array)

### S3/S4 combo for as.logical.Array
as.logical.Array <- function(x, ...) as.vector(x, mode="logical", ...)
setMethod("as.logical", "Array", as.logical.Array)

### S3/S4 combo for as.integer.Array
as.integer.Array <- function(x, ...) as.vector(x, mode="integer", ...)
setMethod("as.integer", "Array", as.integer.Array)

### S3/S4 combo for as.numeric.Array
as.numeric.Array <- function(x, ...) as.vector(x, mode="numeric", ...)
setMethod("as.numeric", "Array", as.numeric.Array)

### S3/S4 combo for as.complex.Array
as.complex.Array <- function(x, ...) as.vector(x, mode="complex", ...)
setMethod("as.complex", "Array", as.complex.Array)

### S3/S4 combo for as.character.Array
as.character.Array <- function(x, ...) as.vector(x, mode="character", ...)
setMethod("as.character", "Array", as.character.Array)

### S3/S4 combo for as.raw.Array
as.raw.Array <- function(x) as.vector(x, mode="raw")
setMethod("as.raw", "Array", as.raw.Array)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### chunkdim() generic and default method
###
### chunkdim(x) must return NULL or an integer vector parallel to dim(x).
###

setGeneric("chunkdim", function(x) standardGeneric("chunkdim"))

setMethod("chunkdim", "ANY", function(x) NULL)

### For use in *Seed classes that use a slot to store the chunkdim. See for
### example the "chunkdim" slot of the HDF5ArraySeed class defined in the
### HDF5Array package.
setClassUnion("integer_OR_NULL", c("integer", "NULL"))

