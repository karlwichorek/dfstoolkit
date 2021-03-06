% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utils.R
\name{weight_def}
\alias{weight_def}
\title{weight_def}
\usage{
weight_def(df, defavg, pts_name, num_start, window, byeweek, def = TRUE)
}
\arguments{
\item{df}{dataframe weight}

\item{defavg}{dataframe containing weekly league averages}

\item{pts_name}{name of column containing fantasy points}

\item{num_start}{name of column that starts stats}

\item{window}{integer 1, 2, or 3 indicating rolling window width}

\item{def}{boolean to send to shift_one or roll_n}
}
\description{
create ddataset for defense
}

