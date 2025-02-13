defmodule FirmowidWeb.HoursRecordHTML do
  use FirmowidWeb, :html

  def preview(assigns) do
    ~H"""
    <FirmowidWeb.HoursRecord.PdfTemplate.hours_record
      name={@name}
      employment_date={@employment_date}
      start_date={@start_date}
      end_date={@end_date}
      hours={@hours}
      avatar_url={@avatar_url}
    />
    """
  end
end
