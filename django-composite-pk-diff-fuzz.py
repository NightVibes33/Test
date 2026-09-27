import django
from django.conf import settings

settings.configure(
    SECRET_KEY="local-composite-diff",
    DATABASES={"default":{"ENGINE":"django.db.backends.sqlite3","NAME":":memory:"}},
    INSTALLED_APPS=[],
    USE_TZ=False,
)
django.setup()

from django.db import connection, models
from django.db.models import Count, F, Q, Window
from django.db.models.functions import RowNumber

class Record(models.Model):
    pk = models.CompositePrimaryKey("tenant_id", "id")
    tenant_id = models.IntegerField()
    id = models.IntegerField()
    secret = models.CharField(max_length=64)
    sort_key = models.IntegerField()
    nullable = models.IntegerField(null=True)

    class Meta:
        app_label="h1diff"
        db_table="h1_record"

with connection.schema_editor() as editor:
    editor.create_model(Record)

Record.objects.bulk_create([
    Record(tenant_id=1,id=1,secret="T1-A",sort_key=40,nullable=None),
    Record(tenant_id=1,id=2,secret="T1-B",sort_key=10,nullable=1),
    Record(tenant_id=1,id=3,secret="T1-C",sort_key=30,nullable=None),
    Record(tenant_id=2,id=1,secret="T2-A",sort_key=20,nullable=2),
    Record(tenant_id=2,id=2,secret="T2-B",sort_key=50,nullable=None),
    Record(tenant_id=2,id=3,secret="T2-C",sort_key=60,nullable=3),
])

def normalize_pk(rows):
    out=[]
    for row in rows:
        row=dict(row)
        pk=row.pop("pk")
        out.append({"tenant_id":pk[0],"id":pk[1],**row})
    return out

def normalize_explicit(rows):
    return [dict(r) for r in rows]

def run(name, short_qs, explicit_qs):
    try:
        short=normalize_pk(list(short_qs))
        short_err=None
    except Exception as e:
        short=None
        short_err=f"{type(e).__name__}: {e}"
    try:
        explicit=normalize_explicit(list(explicit_qs))
        explicit_err=None
    except Exception as e:
        explicit=None
        explicit_err=f"{type(e).__name__}: {e}"

    ok=(short_err==explicit_err and short==explicit)
    print(f"CASE={name}")
    print("SHORT_ERR=",short_err)
    print("EXPLICIT_ERR=",explicit_err)
    print("SHORT=",short)
    print("EXPLICIT=",explicit)
    print("MATCH=",ok)
    print("---")
    return ok, (name, short_err, explicit_err, short, explicit)

base=Record.objects.all()
cases=[]

cases.append((
    "plain",
    base.values("pk","secret").order_by("tenant_id","id"),
    base.values("tenant_id","id","secret").order_by("tenant_id","id"),
))
cases.append((
    "distinct_order_unselected",
    base.values("pk","secret").distinct().order_by("sort_key"),
    base.values("tenant_id","id","secret").distinct().order_by("sort_key"),
))
cases.append((
    "distinct_order_pk",
    base.values("pk","secret").distinct().order_by("pk"),
    base.values("tenant_id","id","secret").distinct().order_by("tenant_id","id"),
))
cases.append((
    "slice_order_unselected",
    base.values("pk","secret").order_by("sort_key")[:4],
    base.values("tenant_id","id","secret").order_by("sort_key")[:4],
))
cases.append((
    "filter_nullable_or",
    base.filter(Q(nullable__isnull=True)|Q(nullable__gte=2)).values("pk","secret").order_by("tenant_id","id"),
    base.filter(Q(nullable__isnull=True)|Q(nullable__gte=2)).values("tenant_id","id","secret").order_by("tenant_id","id"),
))
cases.append((
    "annotate_count",
    base.values("pk","secret").annotate(n=Count("id")).order_by("tenant_id","id"),
    base.values("tenant_id","id","secret").annotate(n=Count("id")).order_by("tenant_id","id"),
))
cases.append((
    "window_no_filter",
    base.annotate(rn=Window(RowNumber(),order_by=F("sort_key").asc()))
        .values("pk","secret","rn").order_by("rn"),
    base.annotate(rn=Window(RowNumber(),order_by=F("sort_key").asc()))
        .values("tenant_id","id","secret","rn").order_by("rn"),
))
cases.append((
    "window_filter",
    base.annotate(rn=Window(RowNumber(),order_by=F("sort_key").asc()))
        .filter(rn__lte=4).values("pk","secret","rn").order_by("rn"),
    base.annotate(rn=Window(RowNumber(),order_by=F("sort_key").asc()))
        .filter(rn__lte=4).values("tenant_id","id","secret","rn").order_by("rn"),
))
cases.append((
    "window_filter_distinct",
    base.annotate(rn=Window(RowNumber(),order_by=F("sort_key").asc()))
        .filter(rn__lte=4).values("pk","secret","rn").distinct().order_by("sort_key"),
    base.annotate(rn=Window(RowNumber(),order_by=F("sort_key").asc()))
        .filter(rn__lte=4).values("tenant_id","id","secret","rn").distinct().order_by("sort_key"),
))

left_short=Record.objects.filter(tenant_id=1).values("pk","secret")
right_short=Record.objects.filter(tenant_id=2).values("pk","secret")
left_exp=Record.objects.filter(tenant_id=1).values("tenant_id","id","secret")
right_exp=Record.objects.filter(tenant_id=2).values("tenant_id","id","secret")
cases.append((
    "union",
    left_short.union(right_short).order_by("secret"),
    left_exp.union(right_exp).order_by("secret"),
))

failures=[]
for args in cases:
    ok, detail=run(*args)
    if not ok:
        failures.append(detail)

print("Django",django.get_version())
print("FAILURE_COUNT=",len(failures))
for f in failures:
    print("MISMATCH_CASE=",f[0])
print("RESULT=" + ("MISMATCHES_FOUND" if failures else "ALL_EQUIVALENT"))
