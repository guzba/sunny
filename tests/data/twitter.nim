import std/options

type
  StatusMetadata* = object
    result_type*: string
    iso_language_code*: string

  EntityUrl* = object
    url*: string
    expanded_url*: string
    display_url*: string
    indices*: seq[int]

  EntityUrlWrap* = object
    urls*: seq[EntityUrl]

  EntityDescription* = object
    urls*: seq[EntityUrl]

  UserEntities* = object
    url*: EntityUrlWrap
    description*: EntityDescription

  User* = object
    id*: int
    id_str*: string
    name*: string
    screen_name*: string
    location*: string
    description*: string
    url*: Option[string]
    entities*: UserEntities
    protected*: bool
    followers_count*: int
    friends_count*: int
    listed_count*: int
    created_at*: string
    favourites_count*: int
    utc_offset*: Option[int]
    time_zone*: Option[string]
    geo_enabled*: bool
    verified*: bool
    statuses_count*: int
    lang*: string
    contributors_enabled*: bool
    is_translator*: bool
    is_translation_enabled*: bool
    profile_background_color*: string
    profile_background_image_url*: string
    profile_background_image_url_https*: string
    profile_background_tile*: bool
    profile_image_url*: string
    profile_image_url_https*: string
    profile_banner_url*: string
    profile_link_color*: string
    profile_sidebar_border_color*: string
    profile_sidebar_fill_color*: string
    profile_text_color*: string
    profile_use_background_image*: bool
    default_profile*: bool
    default_profile_image*: bool
    following*: bool
    follow_request_sent*: bool
    notifications*: bool

  UserMention* = object
    screen_name*: string
    name*: string
    id*: int
    id_str*: string
    indices*: seq[int]

  MediaSize* = object
    w*: int
    h*: int
    resize*: string

  MediaSizes* = object
    medium*: MediaSize
    small*: MediaSize
    thumb*: MediaSize
    large*: MediaSize

  Media* = object
    id*: int
    id_str*: string
    indices*: seq[int]
    media_url*: string
    media_url_https*: string
    url*: string
    display_url*: string
    expanded_url*: string
    `type`*: string
    sizes*: MediaSizes
    source_status_id*: int
    source_status_id_str*: string

  HashTag* = object
    text*: string
    indices*: seq[int]

  StatusEntities* = object
    hashtags*: seq[HashTag]
    symbols*: seq[string]
    urls*: seq[EntityUrl]
    user_mentions*: seq[UserMention]
    media*: seq[Media]

  RetweetedStatus* = object
    metadata*: StatusMetadata
    created_at*: string
    id*: int
    id_str*: string
    text*: string
    source*: string
    truncated*: bool
    in_reply_to_status_id*: Option[int]
    in_reply_to_status_id_str*: Option[string]
    in_reply_to_user_id*: Option[int]
    in_reply_to_user_id_str*: Option[string]
    in_reply_to_screen_name*: Option[string]
    user*: User
    geo*: Option[string]
    coordinates*: Option[string]
    place*: Option[string]
    contributors*: Option[string]
    retweet_count*: int
    favorite_count*: int
    entities*: StatusEntities
    favorited*: bool
    retweeted*: bool
    lang*: string

  Status* = object
    metadata*: StatusMetadata
    created_at*: string
    id*: int
    id_str*: string
    text*: string
    source*: string
    truncated*: bool
    in_reply_to_status_id*: Option[int]
    in_reply_to_status_id_str*: Option[string]
    in_reply_to_user_id*: Option[int]
    in_reply_to_user_id_str*: Option[string]
    in_reply_to_screen_name*: Option[string]
    user*: User
    geo*: Option[string]
    coordinates*: Option[string]
    place*: Option[string]
    contributors*: Option[string]
    retweeted_status*: Option[RetweetedStatus]
    retweet_count*: int
    favorite_count*: int
    entities*: StatusEntities
    favorited*: bool
    retweeted*: bool
    possibly_sensitive*: bool
    lang*: string

  SearchMetadata* = object
    completed_in*: float
    max_id*: int
    max_id_str*: string
    next_results*: string
    query*: string
    refresh_url*: string
    count*: int
    since_id*: int
    since_id_str*: string

  Twitter* = object
    statuses*: seq[Status]
    search_metadata*: SearchMetadata

let twitterJson* = readFile("tests/data/twitter.json")
