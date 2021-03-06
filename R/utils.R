#' @title clean_conns
#' @description function to manage db connections to avoid too many connections
#' error

clean_conns <- function() {
    all_cons <- DBI::dbListConnections(MySQL())
    for (con in all_cons) {
        DBI::dbDisconnect(con)
    }
}

#' @title nfl_query
#' @description
#' \code{nfl_query} a utility function to get data from nfl schema
#'
#' @param query query to send to database
#' @param target_date query will only get data at or after this date. Defaults
#' to start of 2002 NFL season.
#' @return results of query in a dataframe

nfl_query <- function(query, target_date = '2002-09-05') {

    db <- DBI::dbConnect(
        drv = RMySQL::MySQL(),
        user='root',
        password='Datmysqljawn97%!',
        dbname='nfl',
        host='localhost'
    )

    rs <- RMySQL::dbSendQuery(conn = db,
                              statement = query
    )

    data <- RMySQL::fetch(rs, n = -1)

    query_split = unlist(strsplit(query, ' '))
    pos_tables = c('QB', 'RB', 'WR', 'TE')
#     end_date <- as.character(as.POSIXct(target_date) + lubridate::ddays(7))
    if (query_split[match('FROM', query_split) + 1] %in% pos_tables) {
        data <- data %>%
            dplyr::filter(
                date >= target_date#,
                #date < end_date
            )
    }

    RMySQL::dbClearResult(rs)

    clean_conns()

    return(data)
}

#' @title nfl_insert
#' @description \code{nfl_insert} a utility function to insert data into nfl schema
#'
#' @param dataframe a dataframe that contains the data to be inserted into table
#' @param table the name of the table to insert the dataframe into

nfl_insert <- function(dataframe, table) {
    db <- DBI::dbConnect(
        drv = RMySQL::MySQL(),
        user='root',
        password='Datmysqljawn97%!',
        dbname='nfl',
        host='localhost'
    )

    DBI::dbWriteTable(conn = db,
                      name = table,
                      value = dataframe,
                      append = TRUE,
                      row.names=FALSE
    )

    clean_conns()
}

#' @title nba_query
#' @description function to make queries to nba schema
#' @param query query to send to database
#' @return results of query in a dataframe

nba_query <- function(query) {

    db <- DBI::dbConnect(
        drv = RMySQL::MySQL(),
        user='root',
        password='Datmysqljawn97%!',
        dbname='nba',
        host='localhost'
    )

    rs <- RMySQL::dbSendQuery(conn = db,
                              statement = query
    )

    data <- RMySQL::fetch(rs, n = -1)

    RMySQL::dbClearResult(rs)

    clean_conns()

    return(data)
}

#' @title nba_insert
#' @description insert data to nba database
#'
#' @param dataframe dataframe to insert
#' @param table the name of the table to insert into

nba_insert <- function(dataframe, table) {
    db <- DBI::dbConnect(
        drv = RMySQL::MySQL(),
        user='root',
        password='Datmysqljawn97%!',
        dbname='nba',
        host='localhost'
    )

    DBI::dbWriteTable(conn = db,
                      name = table,
                      value = dataframe,
                      append = TRUE,
                      row.names=FALSE
    )

    clean_conns()
}

#' @title add_join_helpers
#' @description function to add season and week columns to assist in creating
#' average tables
#'
#' @param df a dataframe to add the columns to
#' @param sched a dataframe of nfl schedule data

add_join_helpers <- function(df, sched = nfl_query('select * from nflschedule')) {
    season <- sched %>%
        dplyr::filter(
            week == 'season'
        )

    df[, 'year'] <- 0
    for (i in 1:nrow(season)) {
        df$year[df$date >= season$start[i] & df$date <= season$end[i]] <- season$year[i]
    }

    weeks <- sched %>%
        dplyr::filter(
            week != 'season'
        )

    df[, 'week'] <- 0
    for (i in 1:nrow(weeks)) {
        df$week[df$date >= weeks$start[i] & df$date <= weeks$end[i]] <- weeks$week[i]
    }

    return(df)
}

#' @title weight_def
#' @description create ddataset for defense
#'
#' @param df dataframe weight
#' @param defavg dataframe containing weekly league averages
#' @param pts_name name of column containing fantasy points
#' @param num_start name of column that starts stats
#' @param window integer 1, 2, or 3 indicating rolling window width
#' @param def boolean to send to shift_one or roll_n

weight_def <- function(
    df,
    defavg,
    pts_name,
    num_start,
    window,
    byeweek,
    def = TRUE
) {
    pts_ind <- match(pts_name, names(df))
    start <- match(num_start, names(df))
    num_cols <- ncol(df)

    weeks <- df$week
    df_year <- df$year[1]

    defavg <- defavg %>%
        dplyr::filter(
            year == df_year,
            week %in% weeks
        )


    names(defavg) <- paste0('avg_', names(defavg))
    df <- cbind(df, defavg[3:ncol(defavg)])

    for (col in names(df)[start:pts_ind]) {
        df[, col] <- df[, col] / df[, paste0('avg_', col)]
    }

    df <- df[1:num_cols]
    df[is.na(df)] <- 0

    if (window == 1) {
        df <- shift_one(df, pts_name, num_start, def)
    } else if (window == 2) {
        df <- roll_n(df, 2, pts_name, num_start, byeweek, def)
    } else if (window == 3) {
        df <- roll_n(df, 3, pts_name, num_start, byeweek, def)
    } else {
        stop('Window must be 1, 2, or 3.')
    }

    return(df)
}

#' @title fill_def
#' @description if a position registered no stats, fill row
#'
#' @param df dataframe to fill
#' @param full_sched dataframe showing all of team's opponents
#' @param sched dataframe used to add year and week columns

fill_def <- function(
    df,
    full_sched = nfl_query('select * from vegas')
) {
    order <- names(df)
    names(full_sched) <- tolower(names(full_sched))
    base <- full_sched[match(c('date', 'opp', 'team'), names(full_sched))]
    filled <- base %>%
        dplyr::left_join(
            y = df,
            by = c('team' = 'defense', 'date')
        ) %>%
        dplyr::rename(
            defense = team
        )
    filled$offense <- filled$opp
    filled <- filled[-match('opp', names(filled))]

    filled <- filled[match(order, names(filled))]
    filled <- filled %>%
        dplyr::arrange(
            defense,
            date
        )
    full_sched <- full_sched %>%
        dplyr::arrange(
            team,
            date
        )
    filled$home <- full_sched$home
    filled <- filled[-match(c('year', 'week'), names(filled))]
    filled[is.na(filled)] <- 0

    return(filled)
}

#' @title trim_df
#' @description trims dataframe and adds group column
#'
#' @param df dataframe to trim
#'
#' @return trimmed dataframe

trim_df <- function(df) {

    df <- df[!duplicated(df), ]
    df <- df %>%
        dplyr::group_by(
            name,
            team
        )

    trimmer <- function(df) {
        if (nrow(df) > 3) {
            df <- tail(df, n = 3)
            df$group <- 3
        } else if (nrow(df) == 3) {
            df$group <- 3
        } else if (nrow(df) == 2) {
            df$group <- 2
        } else if (nrow(df) == 1) {
            df$group <- 1
        }
        return(df)
    }

    df <- dplyr::do(df, trimmer(.))

    return(df)
}

#' @title roll_n
#' @description find means for players and defenses
#'
#' @param df dataframe to find rolling average
#' @param n number of weeks
#' @param pts_name name of column that contains fantasy points
#' @param num_start name of column that starts stats
#'
#' @return returns rolled dataframe

roll_n <- function(
    df,
    n,
    pts_name,
    num_name
) {
    rolled <- df[nrow(df), ]
    pts_ind <- match(pts_name, names(df))
    start <- match(num_name, names(df))

    fill <- apply(
        df[, start:pts_ind],
        2,
        zoo::rollmean,
        k = n
    ) %>%
        as.data.frame()

    fill <- apply(fill, 2, round, digits = 2)
    rolled[, start:pts_ind] <- fill

    return(rolled)
}

#' @title oppdate_fixer
#' @description updates opponent and date for defenses
#'
#' @param def dataframe of defensive stats
#' @param v vegas dataframe
#' @param bye_teams teams that are on bye
#'
#' @return returns updated dataframe
oppdate_fixer <- function(
    df,
    v,
    bye_teams
) {
    df <- df %>%
        dplyr::filter(
            !(defense %in% bye_teams)
        )

    df <- df %>%
        dplyr::left_join(
            y = v %>%
                dplyr::select(
                    team,
                    date
                ),
            by = c('defense' = 'team')
        ) %>%
        dplyr::rename(
            date = date.x
        )

    df$date <- df$date.y
    df <- df %>%
        dplyr::select(
            -date.y
        )

    for (i in 1:nrow(df)) {
        x <- match(df$defense[i], v$team)
        if ((x %% 2) == 1) {
            df$offense[i] <- v$team[x+1]
        } else if ((x %% 2) == 0) {
            df$offense[i] <- v$team[x-1]
        }
    }

    return(df)
}
