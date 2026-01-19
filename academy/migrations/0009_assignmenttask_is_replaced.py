from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("academy", "0008_add_is_cumulative"),
    ]

    operations = [
        migrations.AddField(
            model_name="assignmenttask",
            name="is_replaced",
            field=models.BooleanField(default=False, verbose_name="대체됨"),
        ),
    ]
